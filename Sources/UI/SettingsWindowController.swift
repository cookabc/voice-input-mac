import AppKit
import SwiftUI

/// Standalone settings window for LLM API configuration + hotkey.
@MainActor
final class SettingsWindowController {

    private var window: NSWindow?
    weak var hotkeyManager: HotkeyManager?

    func showSettings() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsContentView(hotkeyManager: hotkeyManager)
        )

        let win = NSWindow(contentViewController: hostingController)
        win.title = "Murmur Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 440, height: 400))
        win.center()
        win.isReleasedWhenClosed = false

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI settings form

private struct SettingsContentView: View {
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var model: String
    @State private var statusMessage = ""
    @State private var isTesting = false

    // Hotkey
    @State private var hotkeyDisplay: String
    @State private var isRecordingHotkey = false
    private weak var hotkeyManager: HotkeyManager?

    init(hotkeyManager: HotkeyManager?) {
        self.hotkeyManager = hotkeyManager
        let polisher = LLMPolisher.shared
        _baseURL = State(initialValue: polisher.baseURL)
        _apiKey = State(initialValue: polisher.apiKey ?? "")
        _model = State(initialValue: polisher.configuredModel)
        _hotkeyDisplay = State(initialValue: hotkeyManager?.displayString ?? "⌥Space")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ── Hotkey section ──
            VStack(alignment: .leading, spacing: 8) {
                Text("Hotkey (alternative to Fn)")
                    .font(.headline)

                HStack {
                    Text("Shortcut")
                        .frame(width: 70, alignment: .trailing)
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecordingHotkey
                                  ? Color.accentColor.opacity(0.15)
                                  : Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isRecordingHotkey ? Color.accentColor : Color.gray.opacity(0.3))
                            )
                        Text(isRecordingHotkey ? "Press shortcut…" : hotkeyDisplay)
                            .foregroundStyle(isRecordingHotkey ? .secondary : .primary)
                    }
                    .frame(height: 28)
                    .onTapGesture { isRecordingHotkey = true }
                    .background(
                        HotkeyRecorder(
                            isRecording: $isRecordingHotkey,
                            onCaptured: { mods, keyCode in
                                hotkeyManager?.updateShortcut(modifiers: mods, keyCode: keyCode)
                                hotkeyDisplay = hotkeyManager?.displayString ?? "⌥Space"
                            }
                        )
                    )

                    Button("Reset") {
                        hotkeyManager?.resetToDefault()
                        hotkeyDisplay = hotkeyManager?.displayString ?? "⌥Space"
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            // ── LLM section ──
            VStack(alignment: .leading, spacing: 8) {
                Text("LLM API Configuration")
                    .font(.headline)

                fieldRow(label: "Base URL", text: $baseURL)
                fieldRow(label: "API Key", text: $apiKey, secure: true)
                fieldRow(label: "Model", text: $model)
            }

            HStack {
                Button("Test Connection") { testConnection() }
                    .disabled(isTesting)

                Spacer()

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(statusMessage.hasPrefix("✓") ? .green : .secondary)
                }

                Spacer()

                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 400)
    }

    @ViewBuilder
    private func fieldRow(label: String, text: Binding<String>, secure: Bool = false) -> some View {
        HStack {
            Text(label)
                .frame(width: 70, alignment: .trailing)
            if secure {
                SecureField("", text: text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func save() {
        let saved = ConfigManager.shared.saveLLMConfiguration(
            baseURL: baseURL,
            model: model,
            apiKey: apiKey
        )
        statusMessage = saved ? "✓ Saved" : "✗ Saved config, but failed to store API key in Keychain"
    }

    private func testConnection() {
        save()
        guard !statusMessage.hasPrefix("✗") else { return }
        isTesting = true
        statusMessage = "Testing…"
        Task {
            let probe = await LLMPolisher.shared.runtimeProbe()
            statusMessage = probe.isReady ? "✓ \(probe.line)" : "✗ \(probe.line)"
            isTesting = false
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
