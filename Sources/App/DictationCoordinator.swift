import AppKit

@MainActor
final class DictationCoordinator {
    private enum State {
        case idle
        case recording
        case transcribing
        case refining
        case editing
        case inserting
    }

    private let capsulePanel: CapsulePanel
    private let audioSession: AudioSession
    private let transcriber: ColiTranscriber
    private let transcriptEditPanel: TranscriptEditPanelController
    private let configManager: any ConfigManaging
    private let polisher: LLMPolisher

    private var liveSpeech: LiveSpeechRecognizer?
    private var state: State = .idle
    private var processingTask: Task<Void, Never>?

    var selectedLocaleProvider: () -> String = { "zh-CN" }
    var llmEnabledProvider: () -> Bool = { true }
    var runtimeStateSink: (MenuBarController.RuntimeState) -> Void = { _ in }

    init(
        capsulePanel: CapsulePanel,
        audioSession: AudioSession = AudioSession(),
        transcriber: ColiTranscriber = ColiTranscriber(),
        transcriptEditPanel: TranscriptEditPanelController = TranscriptEditPanelController(),
        configManager: any ConfigManaging = ConfigManager.shared,
        polisher: LLMPolisher = .shared
    ) {
        self.capsulePanel = capsulePanel
        self.audioSession = audioSession
        self.transcriber = transcriber
        self.transcriptEditPanel = transcriptEditPanel
        self.configManager = configManager
        self.polisher = polisher
    }

    func handlePrimaryTrigger() {
        switch state {
        case .idle:
            startDictation()
        case .recording:
            stopDictation()
        case .transcribing, .refining, .editing, .inserting:
            break
        }
    }

    func resetLiveSpeechRecognizer() {
        liveSpeech = nil
    }

    func prepareForTermination() {
        processingTask?.cancel()
        processingTask = nil

        let audioPath = audioSession.recordingPath

        if state == .recording {
            audioSession.stopRecording()
            liveSpeech?.stop()
        }

        liveSpeech = nil
        capsulePanel.orderOut(nil)
        capsulePanel.viewModel.audioLevel = 0
        capsulePanel.viewModel.text = ""
        capsulePanel.viewModel.state = .recording
        state = .idle
        runtimeStateSink(.idle)

        if !audioPath.isEmpty {
            try? FileManager.default.removeItem(atPath: audioPath)
        }
    }

    func startDictation() {
        guard state == .idle else { return }
        state = .recording
        runtimeStateSink(.recording)

        audioSession.levelSink = { [weak self] level in
            DispatchQueue.main.async {
                self?.capsulePanel.viewModel.audioLevel = level
            }
        }

        let locale = selectedLocaleProvider()
        if liveSpeech == nil {
            liveSpeech = LiveSpeechRecognizer(locale: locale)
        }
        liveSpeech?.onPartialResult = { [weak self] text in
            guard let self else { return }
            self.capsulePanel.viewModel.text = text
            self.capsulePanel.updateWidth(for: text)
        }

        do {
            let path = try audioSession.startRecording()
            MurmurLogger.speech.info("Recording started: \(path, privacy: .public)")
        } catch {
            MurmurLogger.speech.error("Recording failed: \(error.localizedDescription, privacy: .public)")
            showTransientCapsuleState(.error, text: error.localizedDescription, audioPath: nil)
            return
        }

        audioSession.bufferSink = { [weak self] buffer, time in
            self?.liveSpeech?.appendBuffer(buffer, at: time)
        }
        do {
            try liveSpeech?.start()
        } catch {
            MurmurLogger.speech.error("Live speech start failed: \(error.localizedDescription, privacy: .public)")
        }

        capsulePanel.viewModel.state = .recording
        capsulePanel.viewModel.text = ""
        capsulePanel.viewModel.audioLevel = 0
        capsulePanel.showCapsule()
    }

    func stopDictation() {
        guard state == .recording else { return }
        state = .transcribing

        let audioPath = audioSession.recordingPath
        let liveText = capsulePanel.viewModel.text

        audioSession.stopRecording()
        liveSpeech?.stop()

        capsulePanel.viewModel.state = .transcribing
        capsulePanel.viewModel.audioLevel = 0
        runtimeStateSink(.transcribing)

        processingTask = Task {
            var transcript = liveText
            let speechRuntime = SpeechRuntimeProbe.currentStatus(configManager: configManager)
            let coliPath = speechRuntime.helperPath

            if speechRuntime.isHelperAvailable {
                do {
                    let result = try await transcriber.transcribe(
                        filePath: audioPath,
                        coliPath: coliPath
                    )
                    transcript = result.text
                } catch {
                    MurmurLogger.speech.error("Coli failed, falling back to live text: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                MurmurLogger.speech.error("Coli helper unavailable at \(coliPath, privacy: .public); falling back to live preview text")
            }

            guard !Task.isCancelled else {
                finish(audioPath: audioPath)
                return
            }

            transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                let errorText = speechRuntime.isHelperAvailable
                    ? "No speech detected"
                    : "Speech runtime unavailable. Check Settings > Speech Runtime."
                showTransientCapsuleState(.error, text: errorText, audioPath: audioPath)
                return
            }

            if llmEnabledProvider() {
                state = .refining
                capsulePanel.viewModel.state = .refining
                capsulePanel.viewModel.text = "Refining…"
                runtimeStateSink(.refining)

                do {
                    let dict = DictionaryManager.loadEntries()
                    transcript = try await polisher.polish(
                        text: transcript,
                        dictionary: dict
                    )
                } catch {
                    MurmurLogger.network.error("LLM polish failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            guard !Task.isCancelled else {
                finish(audioPath: audioPath)
                return
            }

            let transcriptAction = await resolveTranscriptAction(transcript)

            guard !Task.isCancelled else {
                finish(audioPath: audioPath)
                return
            }

            switch transcriptAction {
            case .cancel:
                showTransientCapsuleState(.cancelled, text: "Cancelled", audioPath: audioPath, hideAfter: 0.5)
                return
            case .copy(let editedText):
                TextInsertionService.copyToClipboard(editedText)
                showTransientCapsuleState(.success, text: "Copied to clipboard", audioPath: audioPath, hideAfter: 0.8)
                return
            case .insert(let editedText):
                transcript = editedText
            }

            state = .inserting
            switch await injectText(transcript) {
            case .success:
                finish(audioPath: audioPath)
            case .failure(let error):
                MurmurLogger.ui.error("Text insertion failed: \(error.localizedDescription, privacy: .public)")
                showTransientCapsuleState(.error, text: error.localizedDescription, audioPath: audioPath, hideAfter: 1.4)
            }
        }
    }

    func cancelDictation() {
        guard state != .idle else { return }

        processingTask?.cancel()
        processingTask = nil

        let audioPath = audioSession.recordingPath

        if state == .recording {
            audioSession.stopRecording()
            liveSpeech?.stop()
        }

        capsulePanel.viewModel.state = .cancelled
        capsulePanel.viewModel.text = ""
        capsulePanel.viewModel.audioLevel = 0
        showTransientCapsuleState(.cancelled, text: "Cancelled", audioPath: audioPath, hideAfter: 0.5)
    }

    private func resolveTranscriptAction(_ transcript: String) async -> TranscriptEditAction {
        guard configManager.editBeforePaste else {
            return .insert(transcript)
        }

        state = .editing
        runtimeStateSink(.editing)
        capsulePanel.hideCapsule()
        return await transcriptEditPanel.edit(text: transcript)
    }

    private func injectText(_ text: String) async -> Result<Void, Error> {
        let savedIME = IMEService.switchToASCII()
        let savedClipboard = TextInsertionService.saveClipboard()

        TextInsertionService.copyToClipboard(text)

        do {
            try TextInsertionService.simulatePaste()
            try await Task.sleep(nanoseconds: 150_000_000)

            if let saved = savedClipboard {
                TextInsertionService.restoreClipboard(saved)
            }
            if let ime = savedIME {
                IMEService.restore(ime)
            }

            return .success(())
        } catch {
            if let ime = savedIME {
                IMEService.restore(ime)
            }
            return .failure(error)
        }
    }

    private func showTransientCapsuleState(
        _ capsuleState: CapsuleState,
        text: String,
        audioPath: String?,
        hideAfter delay: TimeInterval = 1.0
    ) {
        runtimeStateSink(menuBarRuntimeState(for: capsuleState, text: text))
        capsulePanel.viewModel.state = capsuleState
        capsulePanel.viewModel.text = text
        capsulePanel.viewModel.audioLevel = 0
        capsulePanel.updateWidth(for: text)

        if !capsulePanel.isVisible {
            capsulePanel.showCapsule()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.finish(audioPath: audioPath)
        }
    }

    private func menuBarRuntimeState(for capsuleState: CapsuleState, text: String) -> MenuBarController.RuntimeState {
        switch capsuleState {
        case .recording:
            return .recording
        case .transcribing:
            return .transcribing
        case .refining:
            return .refining
        case .cancelled:
            return .cancelled(text.isEmpty ? "Cancelled" : text)
        case .success:
            return .success(text.isEmpty ? "Done" : text)
        case .error:
            return .error(text.isEmpty ? "Something went wrong" : text)
        }
    }

    private func finish(audioPath: String?) {
        capsulePanel.hideCapsule()
        state = .idle
        runtimeStateSink(.idle)
        processingTask = nil
        if let audioPath {
            try? FileManager.default.removeItem(atPath: audioPath)
        }
    }
}