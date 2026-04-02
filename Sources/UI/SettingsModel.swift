import AppKit
import Observation

@MainActor
@Observable
final class SettingsModel {
    var baseURL: String = ""
    var apiKey: String = ""
    var model: String = ""
    var editBeforePaste: Bool = false
    var speechRuntime: SpeechRuntimeStatus = SpeechRuntimeProbe.currentStatus()
    var statusMessage: String = ""
    var isTesting: Bool = false
    var hotkeyDisplay: String = "⌥Space"
    var isRecordingHotkey: Bool = false

    @ObservationIgnored
    private weak var hotkeyManager: HotkeyManager?

    init(hotkeyManager: HotkeyManager? = nil) {
        self.hotkeyManager = hotkeyManager
        reload()
    }

    func setHotkeyManager(_ hotkeyManager: HotkeyManager?) {
        self.hotkeyManager = hotkeyManager
        hotkeyDisplay = hotkeyManager?.displayString ?? "⌥Space"
    }

    func reload() {
        let polisher = LLMPolisher.shared
        let config = ConfigManager.shared

        baseURL = polisher.baseURL
        apiKey = polisher.apiKey ?? ""
        model = polisher.configuredModel
        editBeforePaste = config.editBeforePaste
        speechRuntime = SpeechRuntimeProbe.currentStatus()
        hotkeyDisplay = hotkeyManager?.displayString ?? "⌥Space"
        statusMessage = ""
        isTesting = false
        isRecordingHotkey = false
    }

    @discardableResult
    func save() -> Bool {
        let saved = ConfigManager.shared.saveLLMConfiguration(
            baseURL: baseURL,
            model: model,
            apiKey: apiKey
        )
        ConfigManager.shared.saveEditBeforePaste(editBeforePaste)
        statusMessage = saved ? "✓ Saved" : "✗ Saved config, but failed to store API key in Keychain"
        return saved
    }

    func testConnection() {
        guard save() else { return }
        isTesting = true
        statusMessage = "Testing…"

        Task {
            let probe = await LLMPolisher.shared.runtimeProbe()
            statusMessage = probe.isReady ? "✓ \(probe.line)" : "✗ \(probe.line)"
            isTesting = false
        }
    }

    func refreshSpeechRuntime() {
        speechRuntime = SpeechRuntimeProbe.currentStatus()
    }

    func applyHotkey(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        hotkeyManager?.updateShortcut(modifiers: modifiers, keyCode: keyCode)
        hotkeyDisplay = hotkeyManager?.displayString ?? "⌥Space"
    }

    func resetHotkey() {
        hotkeyManager?.resetToDefault()
        hotkeyDisplay = hotkeyManager?.displayString ?? "⌥Space"
    }

    func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}