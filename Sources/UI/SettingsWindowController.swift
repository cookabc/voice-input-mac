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
        win.title = String(localized: "Murmur Settings")
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 640, height: 480))
        win.minSize = NSSize(width: 520, height: 380)
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
    case appearance = "Appearance"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .llmAPI:        String(localized: "LLM API")
        case .speechRuntime: String(localized: "Speech Runtime")
        case .speechModels:  String(localized: "Speech Models")
        case .hotkey:        String(localized: "Hotkey")
        case .workflow:      String(localized: "Workflow")
        case .appearance:    String(localized: "Appearance")
        }
    }

    var icon: String {
        switch self {
        case .llmAPI:        "network"
        case .speechRuntime: "waveform"
        case .speechModels:  "arrow.down.circle"
        case .hotkey:        "keyboard"
        case .workflow:      "gearshape.2"
        case .appearance:    "paintpalette"
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
                Label(page.localizedName, systemImage: page.icon)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar(removing: .title)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedPage {
        case .hotkey:        HotkeyPage(model: model)
        case .speechRuntime: SpeechRuntimePage(model: model)
        case .speechModels:  SpeechModelsPage(model: model)
        case .llmAPI:        LLMAPIPage(model: model)
        case .workflow:      WorkflowPage(model: model)
        case .appearance:    AppearancePage(model: model)
        }
    }
}

// MARK: - 1. Hotkey Page

private struct HotkeyPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(String(localized: "Shortcut"))
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
                            .font(.system(size: 13, weight: .semibold))
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

                    Button(String(localized: "Reset")) {
                        model.resetHotkey()
                    }
                    .controlSize(.small)
                }
            } header: {
                Text(String(localized: "Hotkey"))
            } footer: {
                Text(String(localized: "Use a keyboard shortcut as an alternative to holding the Fn key."))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 2. Speech Runtime Page

private struct SpeechRuntimePage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Status")) {
                    Text(model.speechRuntime.summaryLine)
                        .foregroundStyle(model.speechRuntime.isHelperAvailable ? .green : .red)
                }
                LabeledContent(String(localized: "Provider")) {
                    Text(model.speechRuntime.providerIdentifier)
                        .textSelection(.enabled)
                }

                if let modelName = model.speechRuntime.modelName {
                    LabeledContent(String(localized: "Model")) {
                        Text(modelName).textSelection(.enabled)
                    }
                }

                LabeledContent(String(localized: "Model Status")) {
                    Text(model.speechRuntime.modelStatusLine)
                        .foregroundStyle(model.speechRuntime.isModelAvailable ? .green : .red)
                }
                LabeledContent(String(localized: "Helper")) {
                    Text(model.speechRuntime.helperStatusLine)
                        .foregroundStyle(model.speechRuntime.isHelperAvailable ? .green : .red)
                }
                LabeledContent(String(localized: "Origin")) {
                    Text(model.speechRuntime.helperOriginLine).textSelection(.enabled)
                }
                LabeledContent(String(localized: "Path")) {
                    Text(model.speechRuntime.helperPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(String(localized: "Support")) {
                    Text(model.speechRuntime.supportDirectoryPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(String(localized: "Config")) {
                    Text(model.speechRuntime.configFilePath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text(String(localized: "Speech Runtime"))
            } footer: {
                Text(String(localized: "Current final-transcription engine status."))
            }

            Section {
                HStack(spacing: 12) {
                    Button(String(localized: "Refresh Runtime")) { model.refreshSpeechRuntime() }

                    Button(String(localized: "Reveal Helper")) {
                        model.revealInFinder(path: model.speechRuntime.helperPath)
                    }
                    .disabled(!FileManager.default.fileExists(atPath: model.speechRuntime.helperPath))

                    Button(String(localized: "Reveal Support Files")) {
                        model.revealInFinder(path: model.speechRuntime.supportDirectoryPath)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 3. Speech Models Page

private struct SpeechModelsPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            ForEach(model.modelManager.models) { speechModel in
                Section(speechModel.displayName) {
                    LabeledContent(String(localized: "Description")) {
                        Text(speechModel.summary)
                    }
                    LabeledContent(String(localized: "Status")) {
                        modelBadge(for: speechModel)
                    }
                    LabeledContent(String(localized: "Languages")) {
                        Text(speechModel.supportedLanguages)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "Location")) {
                        Text(speechModel.installPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }

                    modelActions(for: speechModel)
                }
            }

            if let activeDownload = model.modelManager.activeDownloadModel {
                Section(String(localized: "Download")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Installing \(activeDownload.displayName)…"))
                            .font(.caption.weight(.semibold))
                        if let progress = model.modelManager.downloadProgress {
                            ProgressView(value: progress)
                        } else {
                            ProgressView()
                        }
                    }
                }
            }

            if !model.modelManager.statusMessage.isEmpty {
                Section {
                    Text(model.modelManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(String(localized: "Reveal Models Folder")) {
                    model.revealInFinder(path: model.modelManager.modelsDirectoryPath)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func modelBadge(for speechModel: SpeechModelState) -> some View {
        if speechModel.isSelected {
            Label(String(localized: "Current"), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        } else if speechModel.isInstalled {
            Label(String(localized: "Installed"), systemImage: "internaldrive.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            Label(String(localized: "Not Installed"), systemImage: "arrow.down.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func modelActions(for speechModel: SpeechModelState) -> some View {
        HStack(spacing: 12) {
            if speechModel.isInstalled {
                Button(speechModel.isSelected ? String(localized: "Current Model") : String(localized: "Use This Model")) {
                    model.selectSpeechModel(speechModel.id)
                }
                .disabled(speechModel.isSelected)
            } else {
                Button(model.modelManager.activeDownloadModel == speechModel.id ? String(localized: "Installing\u{2026}") : String(localized: "Install Model")) {
                    Task { await model.installSpeechModel(speechModel.id) }
                }
                .disabled(model.modelManager.activeDownloadModel != nil)
            }

            Button(String(localized: "Reveal")) {
                model.revealInFinder(path: speechModel.installPath)
            }
            .disabled(!speechModel.isInstalled)
        }
    }
}

// MARK: - 4. LLM API Page

private struct LLMAPIPage: View {
    @Bindable var model: SettingsModel
    @FocusState private var focusedField: LLMField?
    @State private var autoSaveTask: Task<Void, Never>?

    private enum LLMField: Hashable {
        case baseURL, apiKey, modelName
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(String(localized: "Base URL"))
                        .frame(width: 80, alignment: .leading)
                    TextField("https://api.openai.com/v1", text: $model.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .baseURL)
                }

                HStack {
                    Text(String(localized: "API Key"))
                        .frame(width: 80, alignment: .leading)
                    SecureField("sk-…", text: $model.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .apiKey)
                }

                HStack {
                    Text(String(localized: "Model"))
                        .frame(width: 80, alignment: .leading)
                    TextField("gpt-4o-mini", text: $model.model)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .modelName)
                }
            } header: {
                Text(String(localized: "LLM API"))
            } footer: {
                Text(String(localized: "Configure the language model used for text refinement."))
            }

            Section {
                HStack(spacing: 12) {
                    Button(String(localized: "Test Connection")) { model.testConnection() }
                        .disabled(model.isTesting)
                        .accessibilityIdentifier(AccessibilityID.settingsTestConnection)

                    Button(String(localized: "Save")) { model.save() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AccessibilityID.settingsSave)

                    if !model.statusMessage.isEmpty {
                        Text(model.statusMessage)
                            .font(.caption)
                            .foregroundColor(model.statusMessage.hasPrefix("✓") ? .green : .secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: focusedField) { _, newValue in
            autoSaveTask?.cancel()
            if newValue == nil {
                autoSaveTask = Task {
                    try? await Task.sleep(for: .milliseconds(650))
                    guard !Task.isCancelled else { return }
                    model.save()
                }
            }
        }
    }
}

// MARK: - 5. Workflow Page

private struct WorkflowPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { model.editBeforePaste },
                    set: { model.updateEditBeforePaste($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Review Before Paste"))
                        Text(String(localized: "Show a review window before inserting text into the active app."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "Workflow"))
            } footer: {
                Text(String(localized: "Customize how Murmur inserts transcribed text."))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 6. Appearance Page

private struct AppearancePage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section(String(localized: "Theme")) {
                Picker(String(localized: "Appearance"), selection: Binding(
                    get: { model.appTheme },
                    set: { model.updateTheme($0) }
                )) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
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
