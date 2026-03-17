use crate::asr::AsrClient;
use crate::audio;
use serde::Serialize;
use std::process::Command;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeHealth {
    pub ffmpeg_available: bool,
    pub coli_available: bool,
    pub osascript_available: bool,
    pub ready: bool,
    pub issues: Vec<String>,
}

fn command_available(binary: &str) -> bool {
    Command::new("/usr/bin/which")
        .arg(binary)
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

#[tauri::command]
pub fn get_runtime_health() -> RuntimeHealth {
    let ffmpeg_available = audio::check_ffmpeg_available();
    let coli_available = AsrClient::check_availability();
    let osascript_available = command_available("osascript");

    let mut issues = Vec::new();
    if !ffmpeg_available {
        issues.push("ffmpeg is missing. Install it with: brew install ffmpeg".to_string());
    }
    if !coli_available {
        issues.push("coli is missing or unavailable. Install it before starting transcription.".to_string());
    }
    if !osascript_available {
        issues.push("osascript is unavailable, so simulated paste may not work.".to_string());
    }

    RuntimeHealth {
        ffmpeg_available,
        coli_available,
        osascript_available,
        ready: ffmpeg_available && coli_available,
        issues,
    }
}