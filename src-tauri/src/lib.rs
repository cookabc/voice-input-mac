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
use settings::SettingsManager;
use std::sync::Arc;
use tauri::{
    menu::MenuBuilder,
    tray::{MouseButton, MouseButtonState, TrayIconEvent},
    AppHandle, Emitter, Listener, Manager, Runtime, WindowEvent,
};
use tauri_plugin_global_shortcut::ShortcutState;

const MAIN_WINDOW_LABEL: &str = "main";
const MAIN_TRAY_ID: &str = "main";
const TRAY_MENU_SHOW_PANEL: &str = "show-panel";
const TRAY_MENU_TOGGLE_RECORDING: &str = "toggle-recording";
const TRAY_MENU_QUIT: &str = "quit";

fn reveal_main_window<R: Runtime>(app: &AppHandle<R>) {
    if let Some(window) = app.get_webview_window(MAIN_WINDOW_LABEL) {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn toggle_main_window<R: Runtime>(app: &AppHandle<R>) {
    if let Some(window) = app.get_webview_window(MAIN_WINDOW_LABEL) {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            let _ = window.show();
            let _ = window.set_focus();
        }
    }
}

fn trigger_recording_toggle<R: Runtime>(app: &AppHandle<R>) {
    reveal_main_window(app);

    if let Some(window) = app.get_webview_window(MAIN_WINDOW_LABEL) {
        let _ = window.emit("toggle-recording", ());
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let settings_manager = SettingsManager::new();
    let initial_hotkey = settings_manager
        .load_settings()
        .unwrap_or_default()
        .hotkey;

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    if event.state == ShortcutState::Pressed {
                        let _ = app.emit("hotkey-pressed", shortcut.to_string());
                    }
                })
                .build(),
        )
        .on_window_event(|window, event| {
            if window.label() != MAIN_WINDOW_LABEL {
                return;
            }

            match event {
                WindowEvent::CloseRequested { api, .. } => {
                    api.prevent_close();
                    let _ = window.hide();
                }
                WindowEvent::Focused(false) => {
                    let _ = window.hide();
                }
                _ => {}
            }
        })
        .on_menu_event(|app, event| match event.id().as_ref() {
            TRAY_MENU_SHOW_PANEL => reveal_main_window(app),
            TRAY_MENU_TOGGLE_RECORDING => trigger_recording_toggle(app),
            TRAY_MENU_QUIT => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|app, event| {
            if event.id().as_ref() != MAIN_TRAY_ID {
                return;
            }

            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                toggle_main_window(app);
            }
        })
        .setup(move |app| {
            // Initialize state
            app.manage(AudioRecorder::new());
            app.manage(Arc::new(std::sync::Mutex::new(AsrClient::default())));
            let mut hotkey_manager = HotkeyManager::new();
            if let Err(error) = hotkey_manager.register_hotkey(&app.handle().clone(), &initial_hotkey)
            {
                eprintln!("Failed to restore hotkey '{}': {}", initial_hotkey, error);
                hotkey_manager.register_hotkey(&app.handle().clone(), "Command+Shift+V")?;
            }
            app.manage(std::sync::Mutex::new(hotkey_manager));
            app.manage(Arc::new(std::sync::Mutex::new(settings_manager)));

            let window = app
                .get_webview_window(MAIN_WINDOW_LABEL)
                .ok_or("Main window is missing")?;
            let tray_menu = MenuBuilder::new(app)
                .text(TRAY_MENU_SHOW_PANEL, "Show Voice Input")
                .text(TRAY_MENU_TOGGLE_RECORDING, "Start or Stop Recording")
                .separator()
                .text(TRAY_MENU_QUIT, "Quit")
                .build()?;

            if let Some(tray) = app.tray_by_id(MAIN_TRAY_ID) {
                tray.set_menu(Some(tray_menu))?;
                let _ = tray.set_tooltip(Some("Voice Input"));
            }

            let app_handle_for_hotkey = app.handle().clone();
            app.listen("hotkey-pressed", move |_| {
                eprintln!("Hotkey pressed, toggling recording state");

                trigger_recording_toggle(&app_handle_for_hotkey);
            });

            let _ = window.hide();

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
