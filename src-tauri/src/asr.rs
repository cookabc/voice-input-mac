use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Mutex;
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

        eprintln!("Running coli asr with args: {:?}", args);

        let output = timeout(
            Duration::from_secs(120),
            Command::new("coli")
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
        Command::new("coli")
            .arg("--version")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    }

    pub fn set_model(&mut self, model: String) {
        self.model = model;
    }

    pub fn set_polish(&mut self, polish: bool) {
        self.polish = polish;
    }
}

impl Default for AsrClient {
    fn default() -> Self {
        Self::new("sensevoice".to_string(), true)
    }
}

// Thread-safe wrapper for AsrClient
pub struct AsrClientWrapper(Mutex<AsrClient>);

impl AsrClientWrapper {
    pub fn new() -> Self {
        Self(Mutex::new(AsrClient::default()))
    }

    pub async fn transcribe(&self, audio_path: &Path, model: Option<String>, polish: Option<bool>) -> Result<TranscriptionResult, String> {
        let mut client = self.0.lock().map_err(|e| e.to_string())?;

        if let Some(m) = model {
            client.set_model(m);
        }
        if let Some(p) = polish {
            client.set_polish(p);
        }

        client.transcribe(audio_path).await
    }
}

impl Default for AsrClientWrapper {
    fn default() -> Self {
        Self::new()
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
