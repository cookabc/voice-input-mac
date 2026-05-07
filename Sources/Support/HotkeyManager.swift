import AppKit
import Foundation

/// Listens for a user-configured global keyboard shortcut and fires a callback.
///
/// Uses NSEvent global + local monitors — requires Input Monitoring permission on macOS 10.15+.
/// The default shortcut is Option+Space (keyCode 49, modifier .option).
@MainActor
final class HotkeyManager {
    // UserDefaults keys
    private static let udModifiers = "hotkey_modifiers"
    private static let udKeyCode   = "hotkey_keycode"

    // Default: Option + Space
    private static let defaultModifiers: NSEvent.ModifierFlags = .option
    private static let defaultKeyCode: UInt16 = 49  // kVK_Space

    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Called on the main actor when the hotkey fires.
    var onTriggered: (() -> Void)?

    private(set) var modifiers: NSEvent.ModifierFlags
    private(set) var keyCode: UInt16

    init() {
        let savedMods = UserDefaults.standard.object(forKey: Self.udModifiers) as? UInt
        let savedKey  = UserDefaults.standard.object(forKey: Self.udKeyCode) as? UInt16

        modifiers = savedMods.map { NSEvent.ModifierFlags(rawValue: $0) } ?? Self.defaultModifiers
        keyCode   = savedKey ?? Self.defaultKeyCode
    }

    // MARK: - Start / Stop

    func start() {
        stopMonitors()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleEvent(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleEvent(event)
            }
            return event
        }
    }

    func stop() {
        stopMonitors()
    }

    private func stopMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    // MARK: - Event handling

    private func handleEvent(_ event: NSEvent) {
        guard event.keyCode == keyCode else { return }
        // Match required modifiers exactly (ignoring Caps Lock, NumLock etc.)
        let relevant = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard relevant == modifiers else { return }
        onTriggered?()
    }

    // MARK: - Shortcut mutation

    /// Updates the stored shortcut and restarts monitors.
    func updateShortcut(modifiers newMods: NSEvent.ModifierFlags, keyCode newKey: UInt16) {
        modifiers = newMods
        keyCode   = newKey
        UserDefaults.standard.set(newMods.rawValue, forKey: Self.udModifiers)
        UserDefaults.standard.set(newKey, forKey: Self.udKeyCode)
        start()  // restart with new values
    }

    func resetToDefault() {
        updateShortcut(modifiers: Self.defaultModifiers, keyCode: Self.defaultKeyCode)
    }

    // MARK: - Display string

    var displayString: String {
        var parts = [String]()
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeName(keyCode))
        return parts.joined()
    }

    private func keyCodeName(_ code: UInt16) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            // Try to get the character via key code lookup
            let src = CGEventSource(stateID: .hidSystemState)
            if let ev = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true) {
                var len = 0
                var chars = [UniChar](repeating: 0, count: 4)
                ev.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &chars)
                if len > 0, let scalar = Unicode.Scalar(chars[0]), scalar.isASCII {
                    return String(scalar).uppercased()
                }
            }
            return "Key\(code)"
        }
    }
}
