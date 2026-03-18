use std::process::Command;

#[derive(Clone, Default)]
pub struct AudioRecorder;

impl AudioRecorder {
    pub fn new() -> Self {
        Self
    }

    pub fn is_recording(&self) -> bool {
        voice_input_core::is_recording()
    }

    pub fn start_recording(&self) -> Result<String, String> {
        voice_input_core::start_recording()
    }

    pub fn stop_recording(&self) -> Result<(), String> {
        voice_input_core::stop_recording()
    }
}

// Check if ffmpeg is available for audio recording
pub fn check_ffmpeg_available() -> bool {
    voice_input_core::check_ffmpeg_available()
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
