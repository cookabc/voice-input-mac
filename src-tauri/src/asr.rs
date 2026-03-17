use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::path::Path;
use std::path::PathBuf;
use std::process::Command as StdCommand;
use std::time::Duration;
use tokio::process::Command;
use tokio::time::timeout;

#[derive(Debug, Serialize, Deserialize)]
pub struct TranscriptionResult {
    pub text: String,
    pub lang: Option<String>,
    pub duration: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize)]
struct ColiResponse {
    text: String,
    #[serde(rename = "text_clean")]
    text_clean: Option<String>,
    lang: Option<String>,
    duration: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize)]
struct ColiError {
    error: String,
}

pub struct AsrClient {
    model: String,
    polish: bool,
}

impl AsrClient {
    pub fn new(model: String, polish: bool) -> Self {
        Self { model, polish }
    }

    pub async fn transcribe(&self, audio_path: &Path) -> Result<TranscriptionResult, String> {
        if !audio_path.exists() {
            return Err(format!("Audio file not found: {:?}", audio_path));
        }

        let audio_path_str = audio_path
            .to_str()
            .ok_or("Invalid audio path")?;

        // Build the coli asr command
        // Note: polish flag is not supported by coli asr, ignored
        let args = vec![
            "asr",
            "-j", // JSON output
            "--model", &self.model,
            audio_path_str,
        ];

        let coli_executable = Self::resolve_executable_path()
            .ok_or("Failed to locate the coli executable. Install @marswave/coli or expose `coli` on PATH.")?;

        eprintln!("Running coli asr with args: {:?}", args);

        let output = timeout(
            Duration::from_secs(120),
            Command::new(&coli_executable)
                .kill_on_drop(true)
                .args(&args)
                .output(),
        )
        .await
        .map_err(|_| "coli asr timed out after 120 seconds".to_string())?
        .map_err(|e| format!("Failed to execute coli command: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("coli asr failed: {}", stderr));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);

        // Parse JSON response
        if let Ok(response) = serde_json::from_str::<ColiResponse>(&stdout) {
            let text = if self.polish {
                response.text_clean.unwrap_or(response.text)
            } else {
                response.text
            };

            Ok(TranscriptionResult {
                text,
                lang: response.lang,
                duration: response.duration,
            })
        } else if let Ok(error) = serde_json::from_str::<ColiError>(&stdout) {
            Err(error.error)
        } else {
            // Fallback: try to extract text from non-JSON output
            Err(format!("Failed to parse coli response: {}", stdout))
        }
    }

    pub fn check_availability() -> bool {
        Self::resolve_executable_path().is_some()
    }

    pub fn resolve_executable_path() -> Option<PathBuf> {
        if let Some(path) = search_path_for_binary("coli") {
            return Some(path);
        }

        if let Some(nvm_bin) = env::var_os("NVM_BIN") {
            let candidate = PathBuf::from(nvm_bin).join("coli");
            if coli_responds(&candidate) {
                return Some(candidate);
            }
        }

        let home = env::var_os("HOME").map(PathBuf::from);

        if let Some(home_dir) = home.as_ref() {
            if let Some(path) = search_nvm_node_bins(home_dir) {
                return Some(path);
            }

            for relative in [
                ".npm-global/bin/coli",
                ".volta/bin/coli",
                ".local/bin/coli",
            ] {
                let candidate = home_dir.join(relative);
                if coli_responds(&candidate) {
                    return Some(candidate);
                }
            }
        }

        for candidate in ["/opt/homebrew/bin/coli", "/usr/local/bin/coli", "/usr/bin/coli"] {
            let path = PathBuf::from(candidate);
            if coli_responds(&path) {
                return Some(path);
            }
        }

        None
    }

    pub fn set_model(&mut self, model: String) {
        self.model = model;
    }

    pub fn set_polish(&mut self, polish: bool) {
        self.polish = polish;
    }
}

fn search_path_for_binary(binary: &str) -> Option<PathBuf> {
    let path_var = env::var_os("PATH")?;

    env::split_paths(&path_var)
        .map(|entry| entry.join(binary))
        .find(|candidate| coli_responds(candidate))
}

fn search_nvm_node_bins(home_dir: &Path) -> Option<PathBuf> {
    let versions_dir = home_dir.join(".nvm/versions/node");
    let entries = fs::read_dir(versions_dir).ok()?;

    let mut candidates = entries
        .filter_map(|entry| entry.ok().map(|item| item.path().join("bin/coli")))
        .collect::<Vec<_>>();

    candidates.sort_by(|left, right| right.cmp(left));
    candidates.into_iter().find(|candidate| coli_responds(candidate))
}

fn coli_responds(path: &Path) -> bool {
    if !path.is_file() {
        return false;
    }

    StdCommand::new(path)
        .arg("-h")
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

#[cfg(test)]
fn resolve_coli_from_path_var(path_var: Option<std::ffi::OsString>) -> Option<PathBuf> {
    let Some(path_var) = path_var else {
        return None;
    };

    env::split_paths(&path_var)
        .map(|entry| entry.join("coli"))
        .find(|candidate| candidate.is_file())
}

impl Default for AsrClient {
    fn default() -> Self {
        Self::new("sensevoice".to_string(), true)
    }
}

// Tauri commands
#[tauri::command]
pub async fn transcribe_audio(
    audio_path: String,
    model: Option<String>,
    polish: Option<bool>,
    state: tauri::State<'_, std::sync::Arc<std::sync::Mutex<AsrClient>>>,
) -> Result<TranscriptionResult, String> {
    let client = {
        let mut client = state.lock().map_err(|e| e.to_string())?;

        if let Some(m) = model {
            client.set_model(m);
        }
        if let Some(p) = polish {
            client.set_polish(p);
        }

        AsrClient::new(client.model.clone(), client.polish)
    };

    let path = Path::new(&audio_path);
    client.transcribe(path).await
}

#[tauri::command]
pub fn check_coli_available() -> bool {
    AsrClient::check_availability()
}

#[cfg(test)]
mod tests {
    use super::resolve_coli_from_path_var;
    use std::fs;
    use std::ffi::OsString;
    use std::path::PathBuf;

    fn unique_temp_dir(name: &str) -> PathBuf {
        let base = std::env::temp_dir().join(format!("voice-input-mac-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(&base).unwrap();
        base
    }

    #[test]
    fn resolves_coli_from_path_entries() {
        let temp_dir = unique_temp_dir("coli-path");
        let coli_path = temp_dir.join("coli");
        fs::write(&coli_path, b"#!/bin/sh\nexit 0\n").unwrap();

        let path_var = OsString::from(temp_dir.into_os_string());
        let resolved = resolve_coli_from_path_var(Some(path_var)).unwrap();

        assert_eq!(resolved, coli_path);
    }

    #[test]
    fn returns_none_when_path_is_missing() {
        assert!(resolve_coli_from_path_var(None).is_none());
    }
}
