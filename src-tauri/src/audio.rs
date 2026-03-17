use std::path::PathBuf;
use std::process::{Child, Command};
use std::sync::{Arc, Mutex};
use std::time::Instant;

/// Audio recording state (Send + Sync safe)
#[derive(Clone, Default)]
pub struct AudioRecorder {
    inner: Arc<Mutex<AudioRecorderInner>>,
}

struct AudioRecorderInner {
    is_recording: bool,
    current_file: Option<PathBuf>,
    current_process: Option<Child>,
    started_at: Option<Instant>,
}

impl Default for AudioRecorderInner {
    fn default() -> Self {
        Self {
            is_recording: false,
            current_file: None,
            current_process: None,
            started_at: None,
        }
    }
}

impl AudioRecorder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn is_recording(&self) -> bool {
        self.inner.lock().unwrap().is_recording
    }

    pub fn start_recording(&self) -> Result<String, String> {
        let mut inner = self.inner.lock().unwrap();

        if inner.is_recording {
            return Err("Already recording".to_string());
        }

        let temp_dir = std::env::temp_dir();
        let file_path = temp_dir.join(format!(
            "voice_input_{}.wav",
            chrono::Local::now().timestamp_millis()
        ));
        let file_path_str = file_path
            .to_str()
            .ok_or("Failed to create a valid audio path")?
            .to_string();

        // Use `sox` or `ffmpeg` for recording if available
        // Otherwise, use macOS's built-in `afrecord` (deprecated but available)
        // or the modern approach using `avfoundation`

        #[cfg(target_os = "macos")]
        {
            // Try using ffmpeg for audio recording (most reliable)
            let result = Command::new("ffmpeg")
                .args([
                    "-f", "avfoundation",
                    "-i", ":0",
                    "-t", "300", // 5 minutes max
                    "-ac", "1",
                    "-ar", "16000",
                    "-y",
                    &file_path_str,
                ])
                .spawn();

            match result {
                Ok(child) => {
                    inner.is_recording = true;
                    inner.current_file = Some(file_path.clone());
                    inner.current_process = Some(child);
                    inner.started_at = Some(Instant::now());
                    Ok(file_path_str)
                }
                Err(e) => {
                    inner.is_recording = false;
                    inner.current_file = None;
                    inner.current_process = None;
                    inner.started_at = None;

                    Err(format!(
                        "Failed to start ffmpeg recording: {}. Install it with: brew install ffmpeg",
                        e
                    ))
                }
            }
        }

        #[cfg(not(target_os = "macos"))]
        {
            Err("Audio recording only supported on macOS".to_string())
        }
    }

    pub fn stop_recording(&self) -> Result<(), String> {
        let mut inner = self.inner.lock().unwrap();

        if !inner.is_recording {
            return Err("Not recording".to_string());
        }

        #[cfg(target_os = "macos")]
        {
            let mut child = inner
                .current_process
                .take()
                .ok_or("Recording process handle missing")?;

            let pid = child.id() as i32;
            let signal_result = unsafe { libc::kill(pid, libc::SIGINT) };

            if signal_result != 0 {
                return Err(format!(
                    "Failed to signal ffmpeg process {}: {}",
                    pid,
                    std::io::Error::last_os_error()
                ));
            }

            let mut exited = false;
            for _ in 0..20 {
                match child.try_wait() {
                    Ok(Some(status)) => {
                        if !status.success() {
                            eprintln!("ffmpeg exited with status: {}", status);
                        }
                        exited = true;
                        break;
                    }
                    Ok(None) => std::thread::sleep(std::time::Duration::from_millis(100)),
                    Err(e) => {
                        inner.is_recording = false;
                        inner.current_file = None;
                        inner.started_at = None;
                        return Err(format!("Failed while waiting for ffmpeg to exit: {}", e));
                    }
                }
            }

            if !exited {
                child
                    .kill()
                    .map_err(|e| format!("Failed to force-stop ffmpeg: {}", e))?;
                let _ = child.wait();
            }

            inner.is_recording = false;
            inner.current_file = None;
            inner.started_at = None;
            Ok(())
        }

        #[cfg(not(target_os = "macos"))]
        {
            Err("Audio recording only supported on macOS".to_string())
        }
    }

    pub fn get_current_file(&self) -> Option<PathBuf> {
        self.inner.lock().unwrap().current_file.clone()
    }
}

// Alternative: Use AVFoundation via objc for direct recording
// This is a simpler version that avoids Send/Sync issues
#[cfg(target_os = "macos")]
pub mod av_audio {
    use cocoa::base::{id, nil};
    use cocoa::foundation::{NSString};
    use objc::{class, msg_send, sel, sel_impl};
    use std::path::PathBuf;

    pub struct AvAudioRecorder {
        // This struct exists only for the AVFoundation API wrapper
        // We don't store the recorder in Tauri state to avoid Send/Sync issues
    }

    impl AvAudioRecorder {
        pub unsafe fn record_to_file(path: &PathBuf) -> Result<(), String> {
            let ns_path = NSString::alloc(nil).init_str(path.to_str().unwrap());

            let url: id = msg_send![class!(NSURL), fileURLWithPath: ns_path];

            let settings: id = msg_send![class!(NSMutableDictionary), alloc];
            let settings: id = msg_send![settings, init];

            // Configure for WAV output
            let format_key = NSString::alloc(nil).init_str("AVFormatIDKey");
            let linear_pcm: u32 = 0x6c70636d; // 'lpcm'
            let _: () = msg_send![settings, setObject: &(linear_pcm as i32) forKey: format_key];

            let sample_rate_key = NSString::alloc(nil).init_str("AVSampleRateKey");
            let sample_rate: f64 = 16000.0;
            let _: () = msg_send![settings, setObject: &(sample_rate as f64) forKey: sample_rate_key];

            let channels_key = NSString::alloc(nil).init_str("AVNumberOfChannelsKey");
            let channels: u32 = 1;
            let _: () = msg_send![settings, setObject: &(channels as u32) forKey: channels_key];

            let bit_depth_key = NSString::alloc(nil).init_str("AVLinearPCMBitDepthKey");
            let bit_depth: u32 = 16;
            let _: () = msg_send![settings, setObject: &(bit_depth as u32) forKey: bit_depth_key];

            let big_endian_key = NSString::alloc(nil).init_str("AVLinearPCMIsBigEndianKey");
            let _: () = msg_send![settings, setObject: &(false as u8) forKey: big_endian_key];

            let float_key = NSString::alloc(nil).init_str("AVLinearPCMIsFloatKey");
            let _: () = msg_send![settings, setObject: &(false as u8) forKey: float_key];

            let session: id = msg_send![class!(AVAudioSession), sharedInstance];
            let _: () = msg_send![session, setCategory: "record" error: nil];
            let _: () = msg_send![session, setActive: true error: nil];

            let recorder: id = msg_send![class!(AVAudioRecorder), alloc];
            let recorder: id = msg_send![
                recorder,
                initWithURL: url
                settings: settings
                error: nil
            ];

            if recorder != nil {
                let record_result: bool = msg_send![recorder, record];
                if record_result {
                    // Wait for user input to stop
                    // In real use, this would be handled differently
                    Ok(())
                } else {
                    Err("Failed to start recording".to_string())
                }
            } else {
                Err("Failed to create recorder".to_string())
            }
        }
    }
}

// Check if ffmpeg is available for audio recording
pub fn check_ffmpeg_available() -> bool {
    Command::new("ffmpeg")
        .arg("-version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

// Check if sox is available
pub fn check_sox_available() -> bool {
    Command::new("sox")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

// Tauri commands
#[tauri::command]
pub fn start_recording(state: tauri::State<'_, AudioRecorder>) -> Result<String, String> {
    state.start_recording()
}

#[tauri::command]
pub fn stop_recording(state: tauri::State<'_, AudioRecorder>) -> Result<(), String> {
    state.stop_recording()
}

#[tauri::command]
pub fn is_recording(state: tauri::State<'_, AudioRecorder>) -> bool {
    state.is_recording()
}

#[tauri::command]
pub fn check_audio_deps() -> serde_json::Value {
    serde_json::json!({
        "ffmpeg": check_ffmpeg_available(),
        "sox": check_sox_available()
    })
}
