import AppKit
import SwiftUI

/// Standalone settings window for LLM API configuration.
@MainActor
final class SettingsWindowController {

    private var window: NSWindow?

    func showSettings() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsContentView())

        let win = NSWindow(contentViewController: hostingController)
        win.title = "Murmur Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 420, height: 300))
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

    init() {
        let polisher = LLMPolisher.shared
        _baseURL = State(initialValue: polisher.baseURL)
        _apiKey = State(initialValue: polisher.apiKey ?? "")
        _model = State(initialValue: polisher.configuredModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LLM API Configuration")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
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
        .frame(width: 420, height: 300)
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
        LLMPolisher.shared.saveBaseURL(baseURL)
        LLMPolisher.shared.saveApiKey(apiKey)
        LLMPolisher.shared.saveModel(model)
        statusMessage = "✓ Saved"
    }

    private func testConnection() {
        save()
        isTesting = true
        statusMessage = "Testing…"
        Task {
            let probe = await LLMPolisher.shared.runtimeProbe()
            statusMessage = probe.isReady ? "✓ \(probe.line)" : "✗ \(probe.line)"
            isTesting = false
        }
    }
}
