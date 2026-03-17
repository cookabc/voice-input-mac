use serde::{Deserialize, Serialize};
use tauri::AppHandle;
use tauri_plugin_global_shortcut::GlobalShortcutExt;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HotkeyConfig {
    pub accelerator: String,
    pub enabled: bool,
}

impl Default for HotkeyConfig {
    fn default() -> Self {
        Self {
            accelerator: "Cmd+Shift+V".to_string(),
            enabled: true,
        }
    }
}

pub struct HotkeyManager {
    current_hotkey: Option<String>,
}

impl HotkeyManager {
    pub fn new() -> Self {
        Self {
            current_hotkey: None,
        }
    }

    fn normalize_accelerator(accelerator: &str) -> String {
        accelerator
            .split('+')
            .map(|part| match part.trim().to_ascii_lowercase().as_str() {
                "cmd" | "command" => "Command".to_string(),
                "cmdorctrl" | "commandorcontrol" | "commandorctrl" => {
                    "CommandOrControl".to_string()
                }
                "ctrl" | "control" => "Control".to_string(),
                "shift" => "Shift".to_string(),
                "alt" | "option" => "Alt".to_string(),
                "super" => "Super".to_string(),
                "space" => "Space".to_string(),
                key if key.len() == 1 => key.to_ascii_uppercase(),
                key => {
                    let mut chars = key.chars();
                    match chars.next() {
                        Some(first) => format!("{}{}", first.to_ascii_uppercase(), chars.as_str()),
                        None => String::new(),
                    }
                }
            })
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>()
            .join("+")
    }

    pub fn register_hotkey(
        &mut self,
        app_handle: &AppHandle,
        accelerator: &str,
    ) -> Result<(), String> {
        let normalized = Self::normalize_accelerator(accelerator);

        if self.current_hotkey.as_deref() == Some(normalized.as_str()) {
            return Ok(());
        }

        let previous = self.current_hotkey.clone();

        if let Some(existing) = previous.as_deref() {
            if app_handle.global_shortcut().is_registered(existing) {
                app_handle
                    .global_shortcut()
                    .unregister(existing)
                    .map_err(|e| format!("Failed to unregister existing hotkey: {}", e))?;
            }
        }

        match app_handle.global_shortcut().register(normalized.as_str()) {
            Ok(_) => {
                self.current_hotkey = Some(normalized.clone());
                eprintln!("Hotkey registered: {}", normalized);
                Ok(())
            }
            Err(e) => {
                if let Some(existing) = previous {
                    let _ = app_handle.global_shortcut().register(existing.as_str());
                    self.current_hotkey = Some(existing);
                }

                Err(format!("Failed to register hotkey '{}': {}", normalized, e))
            }
        }
    }

    pub fn set_current_hotkey(&mut self, accelerator: String) {
        self.current_hotkey = Some(Self::normalize_accelerator(&accelerator));
    }

    pub fn unregister_hotkey(&mut self, app_handle: &AppHandle) -> Result<(), String> {
        if let Some(accelerator) = self.current_hotkey.as_deref() {
            if app_handle.global_shortcut().is_registered(accelerator) {
                app_handle
                    .global_shortcut()
                    .unregister(accelerator)
                    .map_err(|e| format!("Failed to unregister hotkey: {}", e))?;
            }
        }

        self.current_hotkey = None;
        Ok(())
    }

    pub fn get_current_hotkey(&self) -> Option<&str> {
        self.current_hotkey.as_deref()
    }
}

impl Default for HotkeyManager {
    fn default() -> Self {
        Self::new()
    }
}

#[tauri::command]
pub fn register_hotkey(
    accelerator: String,
    state: tauri::State<'_, std::sync::Mutex<HotkeyManager>>,
    app_handle: AppHandle,
) -> Result<(), String> {
    let mut manager = state.lock().map_err(|e| e.to_string())?;
    manager.register_hotkey(&app_handle, &accelerator)
}

#[tauri::command]
pub fn unregister_hotkey(
    state: tauri::State<'_, std::sync::Mutex<HotkeyManager>>,
    app_handle: AppHandle,
) -> Result<(), String> {
    let mut manager = state.lock().map_err(|e| e.to_string())?;
    manager.unregister_hotkey(&app_handle)
}

#[tauri::command]
pub fn get_current_hotkey(
    state: tauri::State<'_, std::sync::Mutex<HotkeyManager>>,
) -> Option<String> {
    let manager = state.lock().ok()?;
    manager.get_current_hotkey().map(|s| s.to_string())
}
