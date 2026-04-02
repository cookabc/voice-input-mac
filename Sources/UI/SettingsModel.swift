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
    let modelManager: ModelManager

    @ObservationIgnored
    private let configManager: any ConfigManaging

    @ObservationIgnored
    private let polisher: LLMPolisher

    @ObservationIgnored
    private weak var hotkeyManager: HotkeyManager?

    init(
        configManager: any ConfigManaging = ConfigManager.shared,
        polisher: LLMPolisher = .shared,
        hotkeyManager: HotkeyManager? = nil
    ) {
        self.configManager = configManager
        self.polisher = polisher
        self.modelManager = ModelManager(configManager: configManager)
        self.hotkeyManager = hotkeyManager
        reload()
    }

    func setHotkeyManager(_ hotkeyManager: HotkeyManager?) {
        self.hotkeyManager = hotkeyManager
        hotkeyDisplay = hotkeyManager?.displayString ?? "⌥Space"
    }

    func reload() {
        baseURL = polisher.baseURL
        apiKey = polisher.apiKey ?? ""
        model = polisher.configuredModel
        editBeforePaste = configManager.editBeforePaste
        modelManager.refresh()
        speechRuntime = SpeechRuntimeProbe.currentStatus(configManager: configManager)
        hotkeyDisplay = hotkeyManager?.displayString ?? "⌥Space"
        statusMessage = ""
        isTesting = false
        isRecordingHotkey = false
    }

    @discardableResult
    func save() -> Bool {
        let saved = configManager.saveLLMConfiguration(
            baseURL: baseURL,
            model: model,
            apiKey: apiKey
        )
        configManager.saveEditBeforePaste(editBeforePaste)
        statusMessage = saved ? "✓ Saved" : "✗ Saved config, but failed to store API key in Keychain"
        return saved
    }

    func testConnection() {
        guard save() else { return }
        isTesting = true
        statusMessage = "Testing…"

        Task {
            let probe = await polisher.runtimeProbe()
            statusMessage = probe.isReady ? "✓ \(probe.line)" : "✗ \(probe.line)"
            isTesting = false
        }
    }

    func refreshSpeechRuntime() {
        modelManager.refresh()
        speechRuntime = SpeechRuntimeProbe.currentStatus(configManager: configManager)
    }

    func selectSpeechModel(_ identifier: SpeechModelIdentifier) {
        modelManager.selectModel(identifier)
        refreshSpeechRuntime()
    }

    func installSpeechModel(_ identifier: SpeechModelIdentifier) async {
        await modelManager.installModel(identifier)
        refreshSpeechRuntime()
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