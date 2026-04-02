import AppKit
import SwiftUI

/// Standalone settings window for LLM API configuration + hotkey.
@MainActor
final class SettingsWindowController {

    private var window: NSWindow?
    private let configManager: any ConfigManaging
    private let polisher: LLMPolisher
    private lazy var settingsModel = SettingsModel(configManager: configManager, polisher: polisher)
    weak var hotkeyManager: HotkeyManager?

    init(
        configManager: any ConfigManaging = ConfigManager.shared,
        polisher: LLMPolisher = .shared
    ) {
        self.configManager = configManager
        self.polisher = polisher
    }

    func showSettings() {
        settingsModel.setHotkeyManager(hotkeyManager)
        settingsModel.reload()

        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsContentView(model: settingsModel)
        )

        let win = NSWindow(contentViewController: hostingController)
        win.title = "Murmur Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 560, height: 560))
        win.center()
        win.isReleasedWhenClosed = false

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI settings form

private struct SettingsContentView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ── Hotkey section ──
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hotkey (alternative to Fn)")
                        .font(.headline)

                    HStack {
                        Text("Shortcut")
                            .frame(width: 88, alignment: .trailing)
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.isRecordingHotkey
                                      ? Color.accentColor.opacity(0.15)
                                      : Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(model.isRecordingHotkey ? Color.accentColor : Color.gray.opacity(0.3))
                                )
                            Text(model.isRecordingHotkey ? "Press shortcut…" : model.hotkeyDisplay)
                                .foregroundStyle(model.isRecordingHotkey ? .secondary : .primary)
                        }
                        .frame(height: 28)
                        .onTapGesture { model.isRecordingHotkey = true }
                        .background(
                            HotkeyRecorder(
                                isRecording: $model.isRecordingHotkey,
                                onCaptured: { mods, keyCode in
                                    model.applyHotkey(modifiers: mods, keyCode: keyCode)
                                }
                            )
                        )

                        Button("Reset") {
                            model.resetHotkey()
                        }
                        .controlSize(.small)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Speech Runtime")
                        .font(.headline)

                    Text(model.speechRuntime.summaryLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(model.speechRuntime.isHelperAvailable ? Color.green : Color.red)

                    infoRow(label: "Provider", value: model.speechRuntime.providerIdentifier)

                    if let modelName = model.speechRuntime.modelName {
                        infoRow(label: "Model", value: modelName)
                    }

                    infoRow(
                        label: "Helper",
                        value: model.speechRuntime.helperStatusLine,
                        valueColor: model.speechRuntime.isHelperAvailable ? .green : .red,
                        monospaced: false
                    )
                    infoRow(label: "Origin", value: model.speechRuntime.helperOriginLine, monospaced: false)
                    infoRow(label: "Path", value: model.speechRuntime.helperPath)
                    infoRow(label: "Support", value: model.speechRuntime.supportDirectoryPath)
                    infoRow(label: "Config", value: model.speechRuntime.configFilePath)

                    Text("This section mirrors the current final-transcription runtime. Runtime switching and model management will extend from here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Refresh Runtime") { model.refreshSpeechRuntime() }

                        Button("Reveal Helper") {
                            model.revealInFinder(path: model.speechRuntime.helperPath)
                        }
                        .disabled(!FileManager.default.fileExists(atPath: model.speechRuntime.helperPath))

                        Button("Reveal Support Files") {
                            model.revealInFinder(path: model.speechRuntime.supportDirectoryPath)
                        }
                    }
                }

                Divider()

                // ── LLM section ──
                VStack(alignment: .leading, spacing: 8) {
                    Text("LLM API Configuration")
                        .font(.headline)

                    fieldRow(label: "Base URL", text: $model.baseURL)
                    fieldRow(label: "API Key", text: $model.apiKey, secure: true)
                    fieldRow(label: "Model", text: $model.model)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Workflow")
                        .font(.headline)

                    Toggle("Show review window before inserting text", isOn: $model.editBeforePaste)
                }

                HStack {
                    Button("Test Connection") { model.testConnection() }
                        .disabled(model.isTesting)

                    Spacer()

                    if !model.statusMessage.isEmpty {
                        Text(model.statusMessage)
                            .font(.caption)
                            .foregroundColor(model.statusMessage.hasPrefix("✓") ? .green : .secondary)
                    }

                    Spacer()

                    Button("Save") { model.save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 560, height: 560)
    }

    @ViewBuilder
    private func fieldRow(label: String, text: Binding<String>, secure: Bool = false) -> some View {
        HStack {
            Text(label)
                .frame(width: 88, alignment: .trailing)
            if secure {
                SecureField("", text: text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private func infoRow(
        label: String,
        value: String,
        valueColor: Color = .primary,
        monospaced: Bool = true
    ) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 88, alignment: .trailing)
                .foregroundStyle(.secondary)

            if monospaced {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(valueColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(value)
                    .foregroundStyle(valueColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Hotkey recorder (captures a single keyDown via NSEvent local monitor)

private struct HotkeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCaptured: (NSEvent.ModifierFlags, UInt16) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording, context.coordinator.monitor == nil {
            context.coordinator.startListening(binding: $isRecording, onCaptured: onCaptured)
        }
        if !isRecording, context.coordinator.monitor != nil {
            context.coordinator.stopListening()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?

        func startListening(
            binding: Binding<Bool>,
            onCaptured: @escaping (NSEvent.ModifierFlags, UInt16) -> Void
        ) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                // Require at least one modifier.
                guard !mods.isEmpty else { return event }

                onCaptured(mods, event.keyCode)
                binding.wrappedValue = false
                self?.stopListening()
                return nil  // consume the event
            }
        }

        func stopListening() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }

        deinit { stopListening() }
    }
}
