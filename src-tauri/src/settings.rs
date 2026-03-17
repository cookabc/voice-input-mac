use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};
use std::path::PathBuf;
use std::fs;
use std::sync::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub hotkey: String,
    pub model: String,
    pub polish: bool,
    pub auto_paste: bool,
    pub use_applescript: bool,
    pub history_count: usize,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            hotkey: "Cmd+Shift+V".to_string(),
            model: "sensevoice".to_string(),
            polish: true,
            auto_paste: true,
            use_applescript: true,
            history_count: 50,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryEntry {
    pub id: String,
    pub text: String,
    pub timestamp: i64,
    pub lang: Option<String>,
    pub duration: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoreData {
    settings: AppSettings,
    history: Vec<HistoryEntry>,
}

impl Default for StoreData {
    fn default() -> Self {
        Self {
            settings: AppSettings::default(),
            history: Vec::new(),
        }
    }
}

pub struct SettingsManager {
    store_path: PathBuf,
}

impl SettingsManager {
    pub fn new() -> Self {
        let path = if let Some(home) = dirs::home_dir() {
            let mut p = home;
            p.push(".voice-input-mac");
            p.push("settings.json");
            p
        } else {
            let mut p = std::env::temp_dir();
            p.push("voice-input-mac");
            p.push("settings.json");
            p
        };

        // Ensure directory exists
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }

        Self {
            store_path: path,
        }
    }

    fn load_store(&self) -> Result<StoreData, String> {
        if !self.store_path.exists() {
            return Ok(StoreData::default());
        }

        let content = fs::read_to_string(&self.store_path)
            .map_err(|e| format!("Failed to read settings: {}", e))?;

        serde_json::from_str(&content)
            .map_err(|e| format!("Failed to parse settings: {}", e))
    }

    fn save_store(&self, data: &StoreData) -> Result<(), String> {
        let json = serde_json::to_string_pretty(data)
            .map_err(|e| format!("Failed to serialize settings: {}", e))?;

        fs::write(&self.store_path, json)
            .map_err(|e| format!("Failed to write settings: {}", e))
    }

    pub fn load_settings(&self) -> Result<AppSettings, String> {
        let data = self.load_store()?;
        Ok(data.settings)
    }

    pub fn save_settings(&self, settings: &AppSettings) -> Result<(), String> {
        let mut data = self.load_store()?;
        data.settings = settings.clone();
        self.save_store(&data)
    }

    pub fn add_history(&self, entry: &HistoryEntry) -> Result<(), String> {
        let mut data = self.load_store()?;

        // Add new entry at the beginning
        data.history.insert(0, entry.clone());

        // Get history limit from settings
        if data.history.len() > data.settings.history_count {
            data.history.truncate(data.settings.history_count);
        }

        self.save_store(&data)
    }

    pub fn get_history(&self) -> Result<Vec<HistoryEntry>, String> {
        let data = self.load_store()?;
        Ok(data.history)
    }

    pub fn clear_history(&self) -> Result<(), String> {
        let mut data = self.load_store()?;
        data.history.clear();
        self.save_store(&data)
    }

    pub fn delete_history_entry(&self, id: &str) -> Result<(), String> {
        let mut data = self.load_store()?;
        data.history.retain(|entry| entry.id != id);
        self.save_store(&data)
    }
}

impl Default for SettingsManager {
    fn default() -> Self {
        Self::new()
    }
}

// Tauri commands
#[tauri::command]
pub fn get_settings(
    state: tauri::State<'_, std::sync::Arc<Mutex<SettingsManager>>>,
) -> Result<AppSettings, String> {
    let manager = state.lock().map_err(|e| e.to_string())?;
    manager.load_settings()
}

#[tauri::command]
pub fn update_settings(
    settings: AppSettings,
    state: tauri::State<'_, std::sync::Arc<Mutex<SettingsManager>>>,
) -> Result<(), String> {
    let manager = state.lock().map_err(|e| e.to_string())?;
    manager.save_settings(&settings)
}

#[tauri::command]
pub fn get_history(
    state: tauri::State<'_, std::sync::Arc<Mutex<SettingsManager>>>,
) -> Result<Vec<HistoryEntry>, String> {
    let manager = state.lock().map_err(|e| e.to_string())?;
    manager.get_history()
}

#[tauri::command]
pub fn add_history_entry(
    entry: HistoryEntry,
    state: tauri::State<'_, std::sync::Arc<Mutex<SettingsManager>>>,
) -> Result<(), String> {
    let manager = state.lock().map_err(|e| e.to_string())?;
    manager.add_history(&entry)
}

#[tauri::command]
pub fn clear_history(
    state: tauri::State<'_, std::sync::Arc<Mutex<SettingsManager>>>,
) -> Result<(), String> {
    let manager = state.lock().map_err(|e| e.to_string())?;
    manager.clear_history()
}

#[tauri::command]
pub fn delete_history_item(
    id: String,
    state: tauri::State<'_, std::sync::Arc<Mutex<SettingsManager>>>,
) -> Result<(), String> {
    let manager = state.lock().map_err(|e| e.to_string())?;
    manager.delete_history_entry(&id)
}
