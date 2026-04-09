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
    var onEditBeforePasteChanged: ((Bool) -> Void)?

    init(
        configManager: any ConfigManaging = ConfigManager.shared,
        polisher: LLMPolisher = .shared
    ) {
        self.configManager = configManager
        self.polisher = polisher
    }

    func showSettings() {
        settingsModel.onEditBeforePasteChanged = { [weak self] enabled in
            self?.onEditBeforePasteChanged?(enabled)
        }
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
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 720, height: 520))
        win.minSize = NSSize(width: 640, height: 460)
        win.center()
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = true
        win.toolbarStyle = .unified

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Sidebar pages

private enum SettingsPage: String, CaseIterable, Identifiable {
    case llmAPI = "LLM API"
    case speechRuntime = "Speech Runtime"
    case speechModels = "Speech Models"
    case hotkey = "Hotkey"
    case workflow = "Workflow"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .llmAPI:        "network"
        case .speechRuntime: "waveform"
        case .speechModels:  "arrow.down.circle"
        case .hotkey:        "keyboard"
        case .workflow:      "gearshape.2"
        }
    }
}

// MARK: - Root view — sidebar + detail

private struct SettingsContentView: View {
    @Bindable var model: SettingsModel
    @State private var selectedPage: SettingsPage = .llmAPI

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selectedPage) { page in
                Label(page.rawValue, systemImage: page.icon)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                detailContent
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedPage {
        case .hotkey:        HotkeyPage(model: model)
        case .speechRuntime: SpeechRuntimePage(model: model)
        case .speechModels:  SpeechModelsPage(model: model)
        case .llmAPI:        LLMAPIPage(model: model)
        case .workflow:      WorkflowPage(model: model)
        }
    }
}

// MARK: - Page header

private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
}

// MARK: - Grouped card container

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .settingsCard()
    }
}

/// A single row inside a SettingsCard.
private struct CardRow<Content: View>: View {
    var showDivider: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Divider().padding(.leading, 16)
            }
        }
    }
}

// MARK: - 1. Hotkey Page

private struct HotkeyPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Hotkey",
                subtitle: "Use a keyboard shortcut as an alternative to holding the Fn key."
            )

            SettingsCard {
                CardRow(showDivider: false) {
                    Text("Shortcut")
                        .frame(width: 80, alignment: .leading)

                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.isRecordingHotkey
                                  ? Color.accentColor.opacity(0.15)
                                  : Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(model.isRecordingHotkey ? Color.accentColor : Color.gray.opacity(0.22))
                            )

                        Text(model.isRecordingHotkey ? "Press shortcut…" : model.hotkeyDisplay)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(model.isRecordingHotkey ? .secondary : .primary)
                    }
                    .frame(maxWidth: 200, minHeight: 32, maxHeight: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture { model.isRecordingHotkey = true }
                    .background(
                        HotkeyRecorder(
                            isRecording: $model.isRecordingHotkey,
                            onCaptured: { mods, keyCode in
                                model.applyHotkey(modifiers: mods, keyCode: keyCode)
                            }
                        )
                    )

                    Spacer()

                    Button("Reset") {
                        model.resetHotkey()
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - 2. Speech Runtime Page

private struct SpeechRuntimePage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Speech Runtime",
                subtitle: "Current final-transcription engine status."
            )

            SettingsCard {
                runtimeRow(label: "Status", value: model.speechRuntime.summaryLine,
                           color: model.speechRuntime.isHelperAvailable ? .green : .red, showDivider: true)
                runtimeRow(label: "Provider", value: model.speechRuntime.providerIdentifier, showDivider: true)

                if let modelName = model.speechRuntime.modelName {
                    runtimeRow(label: "Model", value: modelName, showDivider: true)
                }

                runtimeRow(label: "Model Status", value: model.speechRuntime.modelStatusLine,
                           color: model.speechRuntime.isModelAvailable ? .green : .red, showDivider: true)
                runtimeRow(label: "Helper", value: model.speechRuntime.helperStatusLine,
                           color: model.speechRuntime.isHelperAvailable ? .green : .red, showDivider: true)
                runtimeRow(label: "Origin", value: model.speechRuntime.helperOriginLine, showDivider: true)
                runtimeRow(label: "Path", value: model.speechRuntime.helperPath, mono: true, showDivider: true)
                runtimeRow(label: "Support", value: model.speechRuntime.supportDirectoryPath, mono: true, showDivider: true)
                runtimeRow(label: "Config", value: model.speechRuntime.configFilePath, mono: true, showDivider: false)
            }

            HStack(spacing: 12) {
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
    }

    @ViewBuilder
    private func runtimeRow(label: String, value: String, color: Color = .primary, mono: Bool = false, showDivider: Bool) -> some View {
        CardRow(showDivider: showDivider) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Group {
                if mono {
                    Text(value).font(.system(.body, design: .monospaced))
                } else {
                    Text(value)
                }
            }
            .foregroundStyle(color)
            .textSelection(.enabled)
            .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - 3. Speech Models Page

private struct SpeechModelsPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Speech Models",
                subtitle: "Manage local ASR models for the final transcription pass."
            )

            ForEach(model.modelManager.models) { speechModel in
                SettingsCard {
                    CardRow(showDivider: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(speechModel.displayName)
                                .font(.headline)
                            Text(speechModel.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        modelBadge(for: speechModel)
                    }

                    CardRow(showDivider: true) {
                        Text("Languages")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(speechModel.supportedLanguages)
                            .multilineTextAlignment(.trailing)
                    }

                    CardRow(showDivider: true) {
                        Text("Location")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(speechModel.installPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }

                    CardRow(showDivider: false) {
                        modelActions(for: speechModel)
                        Spacer()
                    }
                }
            }

            if let activeDownload = model.modelManager.activeDownloadModel {
                SettingsCard {
                    CardRow(showDivider: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Installing \(activeDownload.displayName)…")
                                .font(.caption.weight(.semibold))
                            if let progress = model.modelManager.downloadProgress {
                                ProgressView(value: progress)
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !model.modelManager.statusMessage.isEmpty {
                Text(model.modelManager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Reveal Models Folder") {
                model.revealInFinder(path: model.modelManager.modelsDirectoryPath)
            }
        }
    }

    @ViewBuilder
    private func modelBadge(for speechModel: SpeechModelState) -> some View {
        if speechModel.isSelected {
            Label("Current", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        } else if speechModel.isInstalled {
            Label("Installed", systemImage: "internaldrive.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            Label("Not Installed", systemImage: "arrow.down.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func modelActions(for speechModel: SpeechModelState) -> some View {
        HStack(spacing: 12) {
            if speechModel.isInstalled {
                Button(speechModel.isSelected ? "Current Model" : "Use This Model") {
                    model.selectSpeechModel(speechModel.id)
                }
                .disabled(speechModel.isSelected)
            } else {
                Button(model.modelManager.activeDownloadModel == speechModel.id ? "Installing…" : "Install Model") {
                    Task { await model.installSpeechModel(speechModel.id) }
                }
                .disabled(model.modelManager.activeDownloadModel != nil)
            }

            Button("Reveal") {
                model.revealInFinder(path: speechModel.installPath)
            }
            .disabled(!speechModel.isInstalled)
        }
    }
}

// MARK: - 4. LLM API Page

private struct LLMAPIPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "LLM API",
                subtitle: "Configure the language model used for text refinement."
            )

            SettingsCard {
                CardRow(showDivider: true) {
                    Text("Base URL")
                        .frame(width: 80, alignment: .leading)
                    TextField("https://api.openai.com/v1", text: $model.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                CardRow(showDivider: true) {
                    Text("API Key")
                        .frame(width: 80, alignment: .leading)
                    SecureField("sk-…", text: $model.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                CardRow(showDivider: false) {
                    Text("Model")
                        .frame(width: 80, alignment: .leading)
                    TextField("gpt-4o-mini", text: $model.model)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 12) {
                Button("Test Connection") { model.testConnection() }
                    .disabled(model.isTesting)

                Button("Save") { model.save() }
                    .keyboardShortcut(.defaultAction)

                if !model.statusMessage.isEmpty {
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundColor(model.statusMessage.hasPrefix("✓") ? .green : .secondary)
                }
            }
        }
    }
}

// MARK: - 5. Workflow Page

private struct WorkflowPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Workflow",
                subtitle: "Customize how Murmur inserts transcribed text."
            )

            SettingsCard {
                CardRow(showDivider: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review Before Paste")
                        Text("Show a review window before inserting text into the active app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.editBeforePaste },
                        set: { model.updateEditBeforePaste($0) }
                    ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
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
