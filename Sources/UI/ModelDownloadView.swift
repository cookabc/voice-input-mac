import SwiftUI

struct ModelDownloadView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Speech Models") {
            Text("Murmur still uses the bundled coli runtime today. This manager controls which local ASR model the final transcription pass will use.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(model.modelManager.models) { speechModel in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(speechModel.displayName)
                                .font(.headline)

                            Text(speechModel.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if speechModel.isSelected {
                            Label("Current", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MurmurDesignTokens.Colors.success)
                        } else if speechModel.isInstalled {
                            Label("Installed", systemImage: "internaldrive.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Not Installed", systemImage: "arrow.down.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MurmurDesignTokens.Colors.warning)
                        }
                    }

                    LabeledContent("Languages") {
                        Text(speechModel.supportedLanguages)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Location") {
                        Text(speechModel.installPath)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        if speechModel.isInstalled {
                            Button(speechModel.isSelected ? "Current Model" : "Use This Model") {
                                model.selectSpeechModel(speechModel.id)
                            }
                            .disabled(speechModel.isSelected)
                        } else {
                            Button(model.modelManager.activeDownloadModel == speechModel.id ? "Installing…" : "Install Model") {
                                Task {
                                    await model.installSpeechModel(speechModel.id)
                                }
                            }
                            .disabled(model.modelManager.activeDownloadModel != nil)
                        }

                        Button("Reveal") {
                            model.revealInFinder(path: speechModel.installPath)
                        }
                        .disabled(!speechModel.isInstalled)
                    }
                }
                .padding(.vertical, 4)
            }

            if let activeDownload = model.modelManager.activeDownloadModel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Installing \(activeDownload.displayName)…")
                        .font(.caption.weight(.semibold))

                    if let progress = model.modelManager.downloadProgress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
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
}