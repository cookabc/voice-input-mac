import Carbon
import Foundation

/// Handles CJK input-method switching for safe text insertion.
/// Before pasting, call `switchToASCII()` to avoid triggering the CJK
/// candidate window. After pasting, call `restore(_:)` with the saved
/// source to switch back.
enum IMEService {

    /// Opaque wrapper around a saved TIS input source.
    struct SavedState {
        fileprivate let source: TISInputSource
    }

    /// Returns `true` if the current keyboard input source is a CJK method
    /// (Chinese, Japanese, or Korean).
    static func isCJKActive() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        return isCJK(source)
    }

    /// If the current input source is CJK, switches to an ASCII layout
    /// (ABC or US) and returns the previously-active source so it can be
    /// restored later. Returns `nil` if the source was already ASCII.
    static func switchToASCII() -> SavedState? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard isCJK(current) else { return nil }

        // Find an ASCII-capable keyboard layout.
        let conditions: NSDictionary = [
            kTISPropertyInputSourceCategory! as String: kTISCategoryKeyboardInputSource! as String,
            kTISPropertyInputSourceIsSelectCapable! as String: true,
        ]

        guard let list = TISCreateInputSourceList(conditions as CFDictionary, false)?
                .takeRetainedValue() as? [TISInputSource] else {
            return SavedState(source: current)
        }

        let preferred = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
        for candidate in list {
            guard let rawID = TISGetInputSourceProperty(candidate, kTISPropertyInputSourceID) else {
                continue
            }
            let id = Unmanaged<CFString>.fromOpaque(rawID).takeUnretainedValue() as String
            if preferred.contains(id) {
                TISSelectInputSource(candidate)
                return SavedState(source: current)
            }
        }

        // Fallback: pick the first ASCII layout.
        for candidate in list where !isCJK(candidate) {
            TISSelectInputSource(candidate)
            return SavedState(source: current)
        }

        return SavedState(source: current)
    }

    /// Restores a previously-saved input source.
    static func restore(_ state: SavedState) {
        TISSelectInputSource(state.source)
    }

    // MARK: - Helpers

    private static func isCJK(_ source: TISInputSource) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return false
        }
        let languages = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as NSArray
        let cjkPrefixes = ["zh", "ja", "ko"]
        for lang in languages {
            if let str = lang as? String {
                for prefix in cjkPrefixes where str.hasPrefix(prefix) {
                    return true
                }
            }
        }
        return false
    }
}
