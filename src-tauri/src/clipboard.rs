use std::process::Command;

/// Paste text to the current application using AppleScript
/// This is the most reliable method for cross-app pasting on macOS
pub fn paste_text(text: &str) -> Result<(), String> {
    // First, copy the text to the clipboard using pbcopy
    copy_to_clipboard(text)?;

    // Then simulate Cmd+V using AppleScript
    simulate_cmd_v()
}

/// Simulate Cmd+V keystroke to paste using osascript
fn simulate_cmd_v() -> Result<(), String> {
    let script = r#"
        tell application "System Events"
            keystroke "v" using command down
        end tell
    "#;

    let output = Command::new("osascript")
        .arg("-e")
        .arg(script)
        .output();

    match output {
        Ok(o) if o.status.success() => Ok(()),
        Ok(o) => Err(String::from_utf8_lossy(&o.stderr).to_string()),
        Err(e) => Err(format!("Failed to execute osascript: {}", e)),
    }
}

/// Copy text to the system clipboard using pbcopy
pub fn copy_to_clipboard(text: &str) -> Result<(), String> {
    use std::io::Write;
    use std::process::{Command, Stdio};

    let mut child = Command::new("pbcopy")
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to spawn pbcopy: {}", e))?;

    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(text.as_bytes())
            .map_err(|e| format!("Failed to write to pbcopy: {}", e))?;
    }

    child
        .wait()
        .map_err(|e| format!("Failed to wait for pbcopy: {}", e))?;

    Ok(())
}

/// Get current clipboard content using pbpaste
pub fn get_clipboard_content() -> Result<String, String> {
    let output = Command::new("pbpaste")
        .output()
        .map_err(|e| format!("Failed to execute pbpaste: {}", e))?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    } else {
        Ok(String::new())
    }
}

/// Alternative: Use AppleScript for both copy and paste
pub fn paste_text_applescript(text: &str) -> Result<(), String> {
    // Escape the text for AppleScript
    let escaped_text = text
        .replace('\\', "\\\\")
        .replace('\"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r");

    let script = format!(
        r#"
        set the clipboard to "{}"
        tell application "System Events"
            keystroke "v" using command down
        end tell
        "#,
        escaped_text
    );

    let output = Command::new("osascript")
        .arg("-e")
        .arg(&script)
        .output();

    match output {
        Ok(o) if o.status.success() => Ok(()),
        Ok(o) => Err(String::from_utf8_lossy(&o.stderr).to_string()),
        Err(e) => Err(format!("Failed to execute osascript: {}", e)),
    }
}

// Tauri commands
#[tauri::command]
pub fn paste_transcription(text: String, use_applescript: Option<bool>) -> Result<(), String> {
    if use_applescript.unwrap_or(false) {
        paste_text_applescript(&text)
    } else {
        paste_text(&text)
    }
}

#[tauri::command]
pub fn copy_to_clipboard_cmd(text: String) -> Result<(), String> {
    copy_to_clipboard(&text)
}

#[tauri::command]
pub fn get_clipboard() -> Result<String, String> {
    get_clipboard_content()
}
