use std::path::PathBuf;
use std::process::{Child, Command};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[derive(Default)]
struct AudioRecorderState {
    is_recording: bool,
    current_file: Option<PathBuf>,
    current_process: Option<Child>,
    started_at: Option<Instant>,
}

static AUDIO_RECORDER: OnceLock<Mutex<AudioRecorderState>> = OnceLock::new();

fn audio_recorder() -> &'static Mutex<AudioRecorderState> {
    AUDIO_RECORDER.get_or_init(|| Mutex::new(AudioRecorderState::default()))
}

fn next_recording_path() -> Result<(PathBuf, String), String> {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| format!("Clock error while preparing recording path: {error}"))?
        .as_millis();
    let file_path = std::env::temp_dir().join(format!("voice_input_{millis}.wav"));
    let file_path_str = file_path
        .to_str()
        .ok_or("Failed to create a valid audio path")?
        .to_string();

    Ok((file_path, file_path_str))
}

fn candidate_paths(configured_path: Option<String>) -> Vec<PathBuf> {
    let mut candidates = Vec::new();

    if let Some(path) = configured_path.filter(|value| !value.trim().is_empty()) {
        candidates.push(PathBuf::from(path));
    }

    if let Some(path_var) = std::env::var_os("PATH") {
        candidates.extend(std::env::split_paths(&path_var).map(|entry| entry.join("ffmpeg")));
    }

    for candidate in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] {
        candidates.push(PathBuf::from(candidate));
    }

    candidates
}

fn resolve_ffmpeg_path(configured_path: Option<String>) -> Option<PathBuf> {
    candidate_paths(configured_path)
        .into_iter()
        .find(|candidate| candidate.is_file())
}

pub fn check_ffmpeg_available(configured_path: Option<String>) -> bool {
    resolve_ffmpeg_path(configured_path).is_some()
}

pub fn start_recording(configured_path: Option<String>) -> Result<String, String> {
    let mut recorder = audio_recorder().lock().map_err(|_| "Audio recorder lock poisoned".to_string())?;

    if recorder.is_recording {
        return Err("Already recording".to_string());
    }

    let ffmpeg_path = resolve_ffmpeg_path(configured_path)
        .ok_or("Failed to locate ffmpeg. Bundle it into the app or install it with: brew install ffmpeg")?;
    let (file_path, file_path_str) = next_recording_path()?;

    let child = Command::new(&ffmpeg_path)
        .args([
            "-f",
            "avfoundation",
            "-i",
            ":0",
            "-t",
            "300",
            "-ac",
            "1",
            "-ar",
            "16000",
            "-y",
            &file_path_str,
        ])
        .spawn()
        .map_err(|error| format!("Failed to start ffmpeg recording via {}: {}", ffmpeg_path.display(), error))?;

    recorder.is_recording = true;
    recorder.current_file = Some(file_path);
    recorder.current_process = Some(child);
    recorder.started_at = Some(Instant::now());

    Ok(file_path_str)
}

pub fn stop_recording() -> Result<(), String> {
    let mut recorder = audio_recorder().lock().map_err(|_| "Audio recorder lock poisoned".to_string())?;

    if !recorder.is_recording {
        return Err("Not recording".to_string());
    }

    let mut child = recorder
        .current_process
        .take()
        .ok_or("Recording process handle missing")?;

    let pid = child.id() as i32;
    let signal_result = unsafe { libc::kill(pid, libc::SIGINT) };

    if signal_result != 0 {
        recorder.is_recording = false;
        recorder.current_file = None;
        recorder.started_at = None;
        return Err(format!(
            "Failed to signal ffmpeg process {}: {}",
            pid,
            std::io::Error::last_os_error()
        ));
    }

    let mut exited = false;
    for _ in 0..20 {
        match child.try_wait() {
            Ok(Some(_)) => {
                exited = true;
                break;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(100)),
            Err(error) => {
                recorder.is_recording = false;
                recorder.current_file = None;
                recorder.started_at = None;
                return Err(format!("Failed while waiting for ffmpeg to exit: {}", error));
            }
        }
    }

    if !exited {
        child
            .kill()
            .map_err(|error| format!("Failed to force-stop ffmpeg: {}", error))?;
        let _ = child.wait();
    }

    recorder.is_recording = false;
    recorder.current_file = None;
    recorder.started_at = None;
    Ok(())
}

pub fn is_recording() -> bool {
    audio_recorder()
        .lock()
        .map(|recorder| recorder.is_recording)
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::{candidate_paths, next_recording_path};

    #[test]
    fn prioritizes_configured_ffmpeg_path_in_candidates() {
        let candidates = candidate_paths(Some("/tmp/missing-ffmpeg".into()));
        assert_eq!(candidates.first().map(|value| value.to_string_lossy().to_string()).as_deref(), Some("/tmp/missing-ffmpeg"));
    }

    #[test]
    fn creates_wav_recording_path() {
        let (_, path) = next_recording_path().unwrap();
        assert!(path.ends_with(".wav"));
        assert!(path.contains("voice_input_"));
    }
}