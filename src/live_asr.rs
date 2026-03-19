use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, RwLock,
};
use std::thread::{self, JoinHandle};
use std::time::Duration;

pub struct LiveTranscriptionWorker {
    stop_flag: Arc<AtomicBool>,
    transcript: Arc<RwLock<String>>,
    handle: Option<JoinHandle<()>>,
}

impl LiveTranscriptionWorker {
    pub fn start(
        ffmpeg_path: Option<String>,
        coli_path: Option<String>,
        interval_secs: u64,
    ) -> Self {
        let stop_flag = Arc::new(AtomicBool::new(false));
        let transcript = Arc::new(RwLock::new(String::new()));

        let stop_clone = Arc::clone(&stop_flag);
        let transcript_clone = Arc::clone(&transcript);

        let handle = thread::spawn(move || {
            run_worker(stop_clone, transcript_clone, ffmpeg_path, coli_path, interval_secs);
        });

        Self { stop_flag, transcript, handle: Some(handle) }
    }

    pub fn stop(&mut self) {
        self.stop_flag.store(true, Ordering::Relaxed);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }

    pub fn get_transcript(&self) -> String {
        self.transcript.read().map(|g| g.clone()).unwrap_or_default()
    }
}

impl Drop for LiveTranscriptionWorker {
    fn drop(&mut self) {
        self.stop_flag.store(true, Ordering::Relaxed);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

fn run_worker(
    stop_flag: Arc<AtomicBool>,
    transcript: Arc<RwLock<String>>,
    ffmpeg_path: Option<String>,
    coli_path: Option<String>,
    interval_secs: u64,
) {
    let ffmpeg_exe = ffmpeg_path.unwrap_or_else(|| "ffmpeg".to_string());

    loop {
        if stop_flag.load(Ordering::Relaxed) {
            break;
        }

        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis();
        let temp_path = PathBuf::from(format!("/tmp/voice_live_{ts}.wav"));

        let captured = capture_slice(&ffmpeg_exe, &temp_path, interval_secs, &stop_flag);

        if stop_flag.load(Ordering::Relaxed) {
            let _ = std::fs::remove_file(&temp_path);
            break;
        }

        if captured {
            if let Ok(result) = crate::asr::transcribe_audio(coli_path.clone(), &temp_path, None, None) {
                let text = result.text.trim().to_string();
                if !text.is_empty() {
                    if let Ok(mut guard) = transcript.write() {
                        if guard.is_empty() {
                            *guard = text;
                        } else {
                            guard.push(' ');
                            guard.push_str(&text);
                        }
                    }
                }
            }
        }

        let _ = std::fs::remove_file(&temp_path);
    }
}

fn capture_slice(
    ffmpeg_exe: &str,
    output_path: &std::path::Path,
    duration_secs: u64,
    stop_flag: &Arc<AtomicBool>,
) -> bool {
    let mut child: Child = match Command::new(ffmpeg_exe)
        .args([
            "-f", "avfoundation",
            "-i", ":0",
            "-t", &duration_secs.to_string(),
            "-ac", "1",
            "-ar", "16000",
            "-y",
            output_path.to_str().unwrap_or_default(),
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(c) => c,
        Err(_) => return false,
    };

    loop {
        match child.try_wait() {
            Ok(Some(status)) => return status.success(),
            Ok(None) => {
                if stop_flag.load(Ordering::Relaxed) {
                    let _ = child.kill();
                    let _ = child.wait();
                    return false;
                }
                thread::sleep(Duration::from_millis(100));
            }
            Err(_) => return false,
        }
    }
}
