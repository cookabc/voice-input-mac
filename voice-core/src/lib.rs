mod audio;

use serde::Serialize;
use std::ffi::{c_char, CStr, CString};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock, RwLock};

const CORE_NAME: &str = "voice-input-core";
const CORE_VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Clone, Debug, Default, Serialize)]
struct ToolPaths {
    ffmpeg_path: Option<String>,
    coli_path: Option<String>,
}

#[derive(Debug, Serialize)]
struct SmokeStatus {
    name: &'static str,
    version: &'static str,
    ffmpeg_path: Option<String>,
    coli_path: Option<String>,
    ffmpeg_exists: bool,
    coli_exists: bool,
}

static TOOL_PATHS: OnceLock<RwLock<ToolPaths>> = OnceLock::new();
static LAST_ERROR: OnceLock<Mutex<Option<String>>> = OnceLock::new();

fn tool_paths() -> &'static RwLock<ToolPaths> {
    TOOL_PATHS.get_or_init(|| RwLock::new(ToolPaths::default()))
}

fn last_error() -> &'static Mutex<Option<String>> {
    LAST_ERROR.get_or_init(|| Mutex::new(None))
}

fn c_string_from(value: String) -> *mut c_char {
    CString::new(value)
        .expect("CString::new failed")
        .into_raw()
}

fn optional_string_from_ptr(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }

    let string = unsafe { CStr::from_ptr(value) }.to_string_lossy().trim().to_string();
    if string.is_empty() {
        None
    } else {
        Some(string)
    }
}

fn path_exists(path: Option<&String>) -> bool {
    path.map(PathBuf::from).is_some_and(|value| value.exists())
}

fn set_last_error_message(message: impl Into<String>) {
    if let Ok(mut guard) = last_error().lock() {
        *guard = Some(message.into());
    }
}

fn clear_last_error_message() {
    if let Ok(mut guard) = last_error().lock() {
        *guard = None;
    }
}

pub fn configure_tool_paths(ffmpeg_path: Option<String>, coli_path: Option<String>) -> bool {
    let updated = ToolPaths {
        ffmpeg_path,
        coli_path,
    };

    if let Ok(mut guard) = tool_paths().write() {
        *guard = updated;
        clear_last_error_message();
        true
    } else {
        set_last_error_message("Failed to acquire tool path write lock");
        false
    }
}

pub fn configured_ffmpeg_path() -> Option<String> {
    tool_paths()
        .read()
        .ok()
        .and_then(|guard| guard.ffmpeg_path.clone())
}

pub fn configured_coli_path() -> Option<String> {
    tool_paths()
        .read()
        .ok()
        .and_then(|guard| guard.coli_path.clone())
}

pub fn last_error_message() -> Option<String> {
    last_error().lock().ok().and_then(|guard| guard.clone())
}

pub fn start_recording() -> Result<String, String> {
    audio::start_recording(configured_ffmpeg_path())
        .inspect(|_| clear_last_error_message())
        .inspect_err(|error| set_last_error_message(error.clone()))
}

pub fn stop_recording() -> Result<(), String> {
    audio::stop_recording()
        .inspect(|_| clear_last_error_message())
        .inspect_err(|error| set_last_error_message(error.clone()))
}

pub fn is_recording() -> bool {
    audio::is_recording()
}

pub fn check_ffmpeg_available() -> bool {
    audio::check_ffmpeg_available(configured_ffmpeg_path())
}

#[no_mangle]
pub extern "C" fn voice_input_core_version() -> *mut c_char {
    c_string_from(CORE_VERSION.to_string())
}

#[no_mangle]
pub extern "C" fn voice_input_core_configure_tools(
    ffmpeg_path: *const c_char,
    coli_path: *const c_char,
) -> bool {
    configure_tool_paths(
        optional_string_from_ptr(ffmpeg_path),
        optional_string_from_ptr(coli_path),
    )
}

#[no_mangle]
pub extern "C" fn voice_input_core_smoke_status_json() -> *mut c_char {
    let tool_paths = tool_paths()
        .read()
        .map(|guard| guard.clone())
        .unwrap_or_default();

    let status = SmokeStatus {
        name: CORE_NAME,
        version: CORE_VERSION,
        ffmpeg_exists: path_exists(tool_paths.ffmpeg_path.as_ref()),
        coli_exists: path_exists(tool_paths.coli_path.as_ref()),
        ffmpeg_path: tool_paths.ffmpeg_path,
        coli_path: tool_paths.coli_path,
    };

    c_string_from(serde_json::to_string(&status).expect("serialize smoke status"))
}

#[no_mangle]
pub extern "C" fn voice_input_core_last_error_message() -> *mut c_char {
    c_string_from(last_error_message().unwrap_or_default())
}

#[no_mangle]
pub extern "C" fn voice_input_core_start_recording() -> *mut c_char {
    match start_recording() {
        Ok(path) => c_string_from(path),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn voice_input_core_stop_recording() -> bool {
    stop_recording().is_ok()
}

#[no_mangle]
pub extern "C" fn voice_input_core_is_recording() -> bool {
    is_recording()
}

#[no_mangle]
pub extern "C" fn voice_input_core_string_free(value: *mut c_char) {
    if value.is_null() {
        return;
    }

    unsafe {
        let _ = CString::from_raw(value);
    }
}

#[cfg(test)]
mod tests {
    use super::{configure_tool_paths, last_error_message, tool_paths};

    #[test]
    fn stores_tool_configuration() {
        configure_tool_paths(Some("/tmp/ffmpeg".into()), Some("/tmp/coli".into()));

        let guard = tool_paths().read().unwrap();

        assert_eq!(guard.ffmpeg_path.as_deref(), Some("/tmp/ffmpeg"));
        assert_eq!(guard.coli_path.as_deref(), Some("/tmp/coli"));
    }

    #[test]
    fn last_error_defaults_to_none() {
        configure_tool_paths(None, None);
        assert!(last_error_message().is_none());
    }
}
