use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::fs;
use std::sync::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub hotkey: String,
    pub model: String,
    pub polish: bool,
    #[serde(alias = "auto_paste")]
    pub auto_paste: bool,
    #[serde(alias = "use_applescript")]
    pub use_applescript: bool,
    #[serde(alias = "history_count")]
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
    #[serde(default = "default_store_version")]
    version: u8,
    settings: AppSettings,
    history: Vec<HistoryEntry>,
}

fn default_store_version() -> u8 {
    1
}

impl Default for StoreData {
    fn default() -> Self {
        Self {
            version: default_store_version(),
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

        Self::new_with_path(path)
    }

    pub fn new_with_path(store_path: PathBuf) -> Self {
        if let Some(parent) = store_path.parent() {
            let _ = fs::create_dir_all(parent);
        }

        Self { store_path }
    }

    fn load_store(&self) -> Result<StoreData, String> {
        if !self.store_path.exists() {
            return Ok(StoreData::default());
        }

        let content = fs::read_to_string(&self.store_path)
            .map_err(|e| format!("Failed to read settings: {}", e))?;

        match serde_json::from_str(&content) {
            Ok(data) => Ok(data),
            Err(e) => {
                self.backup_corrupted_store()?;
                eprintln!("Settings store was corrupted and has been reset: {}", e);
                Ok(StoreData::default())
            }
        }
    }

    fn save_store(&self, data: &StoreData) -> Result<(), String> {
        let json = serde_json::to_string_pretty(data)
            .map_err(|e| format!("Failed to serialize settings: {}", e))?;

        let file_name = self
            .store_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("settings.json");
        let temp_path = self
            .store_path
            .with_file_name(format!("{}.tmp", file_name));

        fs::write(&temp_path, json)
            .map_err(|e| format!("Failed to write temporary settings: {}", e))?;

        fs::rename(&temp_path, &self.store_path)
            .map_err(|e| format!("Failed to replace settings atomically: {}", e))?;

        Ok(())
    }

    fn backup_corrupted_store(&self) -> Result<(), String> {
        let file_name = self
            .store_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("settings.json");
        let backup_path = self.store_path.with_file_name(format!(
            "{}.corrupt-{}",
            file_name,
            chrono::Local::now().timestamp_millis()
        ));

        fs::rename(&self.store_path, backup_path)
            .map_err(|e| format!("Failed to back up corrupted settings: {}", e))
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn test_store_path(test_name: &str) -> PathBuf {
        let millis = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis();

        std::env::temp_dir()
            .join("voice-input-mac-tests")
            .join(format!("{}-{}", test_name, millis))
            .join("settings.json")
    }

    #[test]
    fn loads_legacy_snake_case_settings() {
        let store_path = test_store_path("legacy-settings");
        let manager = SettingsManager::new_with_path(store_path.clone());

        let legacy_store = r#"{
  "settings": {
    "hotkey": "Cmd+Shift+V",
    "model": "sensevoice",
    "polish": true,
    "auto_paste": false,
    "use_applescript": false,
    "history_count": 25
  },
  "history": []
}"#;

        fs::write(&store_path, legacy_store).unwrap();

        let settings = manager.load_settings().unwrap();
        assert_eq!(settings.hotkey, "Cmd+Shift+V");
        assert!(!settings.auto_paste);
        assert!(!settings.use_applescript);
        assert_eq!(settings.history_count, 25);
    }

    #[test]
    fn save_store_round_trips_and_cleans_temp_file() {
        let store_path = test_store_path("roundtrip");
        let manager = SettingsManager::new_with_path(store_path.clone());

        let settings = AppSettings {
            hotkey: "Command+Shift+V".to_string(),
            model: "whisper".to_string(),
            polish: false,
            auto_paste: false,
            use_applescript: false,
            history_count: 12,
        };

        manager.save_settings(&settings).unwrap();
        let loaded = manager.load_settings().unwrap();

        assert_eq!(loaded.hotkey, settings.hotkey);
        assert_eq!(loaded.model, settings.model);
        assert_eq!(loaded.history_count, settings.history_count);

        let temp_path = store_path.with_file_name("settings.json.tmp");
        assert!(!temp_path.exists());
    }

    #[test]
    fn corrupted_store_is_backed_up_and_reset() {
        let store_path = test_store_path("corrupted");
        let manager = SettingsManager::new_with_path(store_path.clone());

        fs::write(&store_path, "{not-valid-json").unwrap();

        let settings = manager.load_settings().unwrap();
        assert_eq!(settings.hotkey, AppSettings::default().hotkey);

        let parent = store_path.parent().unwrap();
        let mut backup_found = false;
        for entry in fs::read_dir(parent).unwrap() {
            let path = entry.unwrap().path();
            if path
                .file_name()
                .and_then(|name| name.to_str())
                .map(|name| name.starts_with("settings.json.corrupt-"))
                .unwrap_or(false)
            {
                backup_found = true;
            }
        }

        assert!(backup_found);
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
