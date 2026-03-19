mod audio;
mod asr;
mod live_asr;

use serde::Serialize;
use std::ffi::{c_char, CStr, CString};
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

pub use asr::TranscriptionResult;

static TOOL_PATHS: OnceLock<RwLock<ToolPaths>> = OnceLock::new();
static LAST_ERROR: OnceLock<Mutex<Option<String>>> = OnceLock::new();
static LIVE_WORKER: OnceLock<Mutex<Option<live_asr::LiveTranscriptionWorker>>> = OnceLock::new();

fn tool_paths() -> &'static RwLock<ToolPaths> {
    TOOL_PATHS.get_or_init(|| RwLock::new(ToolPaths::default()))
}

fn last_error() -> &'static Mutex<Option<String>> {
    LAST_ERROR.get_or_init(|| Mutex::new(None))
}

fn live_worker() -> &'static Mutex<Option<live_asr::LiveTranscriptionWorker>> {
    LIVE_WORKER.get_or_init(|| Mutex::new(None))
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

pub fn check_coli_available() -> bool {
    asr::check_coli_available(configured_coli_path())
}

pub fn transcribe_audio(
    audio_path: impl AsRef<std::path::Path>,
    model: Option<String>,
    polish: Option<bool>,
) -> Result<TranscriptionResult, String> {
    asr::transcribe_audio(configured_coli_path(), audio_path.as_ref(), model, polish)
        .inspect(|_| clear_last_error_message())
        .inspect_err(|error| set_last_error_message(error.clone()))
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
        ffmpeg_exists: check_ffmpeg_available(),
        coli_exists: check_coli_available(),
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
pub extern "C" fn voice_input_core_transcribe_audio(
    audio_path: *const c_char,
    model: *const c_char,
    polish: bool,
) -> *mut c_char {
    let Some(audio_path) = optional_string_from_ptr(audio_path) else {
        set_last_error_message("Audio path is required");
        return std::ptr::null_mut();
    };

    match transcribe_audio(audio_path, optional_string_from_ptr(model), Some(polish)) {
        Ok(result) => c_string_from(
            serde_json::to_string(&result).expect("serialize transcription result"),
        ),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn voice_input_core_start_live_transcription() -> bool {
    let worker = live_asr::LiveTranscriptionWorker::start(
        configured_ffmpeg_path(),
        configured_coli_path(),
        5,
    );
    match live_worker().lock() {
        Ok(mut guard) => {
            *guard = Some(worker);
            clear_last_error_message();
            true
        }
        Err(_) => {
            set_last_error_message("Failed to acquire live worker lock");
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn voice_input_core_stop_live_transcription() -> bool {
    match live_worker().lock() {
        Ok(mut guard) => {
            if let Some(mut worker) = guard.take() {
                worker.stop();
            }
            clear_last_error_message();
            true
        }
        Err(_) => {
            set_last_error_message("Failed to acquire live worker lock");
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn voice_input_core_get_partial_transcript() -> *mut c_char {
    if let Ok(guard) = live_worker().lock() {
        if let Some(ref worker) = *guard {
            return c_string_from(worker.get_transcript());
        }
    }
    c_string_from(String::new())
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
