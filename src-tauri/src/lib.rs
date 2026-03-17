// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod audio;
mod asr;
mod clipboard;
mod health;
mod hotkey;
mod settings;

use audio::AudioRecorder;
use asr::AsrClient;
use hotkey::HotkeyManager;
use settings::{AppSettings, HistoryEntry, SettingsManager};
use std::sync::Arc;
use tauri::{Emitter, Listener, Manager, State, AppHandle};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            // Initialize state
            app.manage(AudioRecorder::new());
            app.manage(Arc::new(std::sync::Mutex::new(AsrClient::default())));
            app.manage(std::sync::Mutex::new(HotkeyManager::new()));
            app.manage(Arc::new(std::sync::Mutex::new(SettingsManager::new())));

            // Listen for hotkey events
            let app_handle_for_hotkey = app.handle().clone();
            app.listen("hotkey-pressed", move |_| {
                eprintln!("Hotkey pressed, toggling recording window");

                if let Some(window) = app_handle_for_hotkey.get_webview_window("main") {
                    if window.is_visible().unwrap_or(false) {
                        let _ = window.hide();
                    } else {
                        let _ = window.show();
                        let _ = window.set_focus();
                        // Emit event to frontend to start/stop recording
                        let _ = window.emit("toggle-recording", ());
                    }
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            // Audio commands
            audio::start_recording,
            audio::stop_recording,
            audio::is_recording,
            audio::check_audio_deps,
            // ASR commands
            asr::transcribe_audio,
            asr::check_coli_available,
            health::get_runtime_health,
            // Clipboard commands
            clipboard::paste_transcription,
            clipboard::copy_to_clipboard_cmd,
            clipboard::get_clipboard,
            // Hotkey commands
            hotkey::register_hotkey,
            hotkey::unregister_hotkey,
            hotkey::get_current_hotkey,
            // Settings commands
            settings::get_settings,
            settings::update_settings,
            settings::get_history,
            settings::add_history_entry,
            settings::clear_history,
            settings::delete_history_item,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
