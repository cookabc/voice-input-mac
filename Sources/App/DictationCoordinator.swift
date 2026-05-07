import AppKit

@MainActor
final class DictationCoordinator {
    private let capsulePanel: CapsulePanel
    private let audioSession: any AudioRecording
    private let finalTranscriptionEngine: any FinalTranscriptionEngine
    private let transcriptEditPanel: TranscriptEditPanelController
    private let configManager: any ConfigManaging
    private let polisher: any TextPolishing

    private var liveSpeech: LiveSpeechRecognizer?
    private(set) var phase: DictationPhase = .idle
    private var processingTask: Task<Void, Never>?
    private var textInsertionTarget: TextInsertionTarget?

    var selectedLocaleProvider: () -> String = { "zh-CN" }
    var llmEnabledProvider: () -> Bool = { true }

    /// Attached by AppDelegate so the menu bar tracks phase changes.
    weak var menuBar: MenuBarController?

    init(
        capsulePanel: CapsulePanel,
        audioSession: any AudioRecording = AudioSession(),
        finalTranscriptionEngine: any FinalTranscriptionEngine = ColiTranscriber(),
        transcriptEditPanel: TranscriptEditPanelController = TranscriptEditPanelController(),
        configManager: any ConfigManaging = ConfigManager.shared,
        polisher: any TextPolishing = LLMPolisher.shared
    ) {
        self.capsulePanel = capsulePanel
        self.audioSession = audioSession
        self.finalTranscriptionEngine = finalTranscriptionEngine
        self.transcriptEditPanel = transcriptEditPanel
        self.configManager = configManager
        self.polisher = polisher
    }

    // MARK: - Single phase setter (replaces 6 scattered assignments)

    private func setPhase(_ newPhase: DictationPhase, text: String? = nil) {
        phase = newPhase
        capsulePanel.viewModel.phase = newPhase
        if let text {
            capsulePanel.viewModel.text = text
        } else if let pinnedText = newPhase.pinnedCapsuleText {
            capsulePanel.viewModel.text = pinnedText
        } else if newPhase != .recording {
            capsulePanel.viewModel.text = ""
        }
        if newPhase != .recording { capsulePanel.viewModel.audioLevel = 0 }
        let displayText = capsulePanel.viewModel.text.isEmpty
            ? newPhase.capsuleDetailPlaceholder
            : capsulePanel.viewModel.text
        capsulePanel.updateWidth(for: displayText, animated: false)
        menuBar?.setPhase(newPhase)
    }

    // MARK: - Public API

    func handlePrimaryTrigger() {
        switch phase {
        case .idle:
            startDictation()
        case .recording:
            stopDictation()
        default:
            break
        }
    }

    func resetLiveSpeechRecognizer() {
        liveSpeech = nil
    }

    func prepareForTermination() {
        processingTask?.cancel()
        processingTask = nil
        textInsertionTarget = nil

        let audioPath = audioSession.recordingPath

        if phase == .recording {
            audioSession.stopRecording()
            liveSpeech?.stop()
        }

        liveSpeech = nil
        capsulePanel.orderOut(nil)
        capsulePanel.viewModel.audioLevel = 0
        capsulePanel.viewModel.text = ""
        setPhase(.idle)

        if !audioPath.isEmpty {
            try? FileManager.default.removeItem(atPath: audioPath)
        }
    }

    func startDictation() {
        guard phase == .idle else { return }
        textInsertionTarget = TextInsertionService.captureFrontmostTarget()
        if let target = textInsertionTarget {
            MurmurLogger.ui.info("Captured insertion target: \(target.displayName, privacy: .public) [pid: \(target.processIdentifier)]")
        }
        setPhase(.recording, text: "")

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
            guard self.phase == .recording else { return }
            self.capsulePanel.viewModel.text = text
            self.capsulePanel.updateWidth(for: text, animated: false)
        }

        // Start live speech FIRST so its request exists before audio buffers arrive.
        do {
            try liveSpeech?.start()
        } catch {
            MurmurLogger.speech.error("Live speech start failed: \(error.localizedDescription, privacy: .public)")
        }

        audioSession.bufferSink = { [weak self] buffer, time in
            self?.liveSpeech?.appendBuffer(buffer, at: time)
        }

        do {
            let path = try audioSession.startRecording()
            MurmurLogger.speech.info("Recording started: \(path, privacy: .public)")
        } catch {
            MurmurLogger.speech.error("Recording failed: \(error.localizedDescription, privacy: .public)")
            liveSpeech?.stop()
            showTransientPhase(.failed(error.localizedDescription), audioPath: nil)
            return
        }

        capsulePanel.showCapsule()
    }

    func stopDictation() {
        guard phase == .recording else { return }

        let audioPath = audioSession.recordingPath
        // Capture live text NOW, before setPhase wipes it.
        let liveText = capsulePanel.viewModel.text

        audioSession.stopRecording()
        liveSpeech?.stop()

        MurmurLogger.speech.error("Pipeline: stopDictation (liveText='\(liveText, privacy: .public)', audioPath=\(audioPath, privacy: .public))")

        setPhase(.transcribing)

        let finalTranscriptionEngine = self.finalTranscriptionEngine

        processingTask = Task {
            var transcript = liveText
            let speechRuntime = SpeechRuntimeProbe.currentStatus(configManager: configManager)
            let selectedModel = SpeechModelIdentifier(providerIdentifier: speechRuntime.providerIdentifier)?.rawValue
                ?? ColiTranscriber.defaultModel
            let modelIdentifier = SpeechModelIdentifier(rawValue: selectedModel) ?? .sensevoice

            MurmurLogger.speech.error("Pipeline: transcribing (liveText length=\(liveText.count), coli available=\(speechRuntime.isHelperAvailable && speechRuntime.isModelAvailable))")

            if speechRuntime.isHelperAvailable && speechRuntime.isModelAvailable {
                do {
                    let result = try await finalTranscriptionEngine.transcribe(
                        FinalTranscriptionRequest(
                            filePath: audioPath,
                            runtime: speechRuntime,
                            selectedModel: modelIdentifier
                        )
                    )
                    let coliText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !coliText.isEmpty {
                        transcript = coliText
                        MurmurLogger.speech.error("Pipeline: coli transcription complete (\(coliText.count) chars): '\(coliText, privacy: .public)'")
                    } else {
                        MurmurLogger.speech.error("Pipeline: coli returned empty, keeping liveText (\(liveText.count) chars)")
                    }
                } catch {
                    MurmurLogger.speech.error("Coli failed, falling back to live text: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                MurmurLogger.speech.error("Coli runtime unavailable at \(speechRuntime.helperPath, privacy: .public); falling back to live preview text")
            }

            guard !Task.isCancelled else {
                MurmurLogger.speech.info("Pipeline: cancelled after transcription")
                finish(audioPath: audioPath)
                return
            }

            transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                let errorText = (speechRuntime.isHelperAvailable && speechRuntime.isModelAvailable)
                    ? "No speech detected"
                    : "Speech runtime unavailable. Check Settings > Speech Models."
                MurmurLogger.speech.error("Pipeline: empty transcript — \(errorText, privacy: .public)")
                showTransientPhase(.failed(errorText), audioPath: audioPath)
                return
            }

            if llmEnabledProvider() {
                MurmurLogger.speech.error("Pipeline: refining via LLM")
                setPhase(.refining, text: "Refining…")

                do {
                    let dict = DictionaryManager.loadEntries()
                    transcript = try await polisher.polish(
                        text: transcript,
                        dictionary: dict
                    )
                    MurmurLogger.speech.error("Pipeline: LLM polish complete (\(transcript.count) chars)")
                } catch {
                    MurmurLogger.network.error("LLM polish failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            guard !Task.isCancelled else {
                MurmurLogger.speech.error("Pipeline: cancelled after polish")
                finish(audioPath: audioPath)
                return
            }

            let transcriptAction = await resolveTranscriptAction(transcript)
            MurmurLogger.ui.error("Pipeline: transcript action resolved: \(String(describing: transcriptAction), privacy: .public)")

            guard !Task.isCancelled else {
                MurmurLogger.speech.error("Pipeline: cancelled after action resolution")
                finish(audioPath: audioPath)
                return
            }

            switch transcriptAction {
            case .cancel:
                showTransientPhase(.cancelled("Cancelled"), audioPath: audioPath, hideAfter: 0.5)
                return
            case .copy(let editedText):
                TextInsertionService.copyToClipboard(editedText)
                showTransientPhase(.completed("Copied to clipboard"), audioPath: audioPath, hideAfter: 0.8)
                return
            case .insert(let editedText):
                transcript = editedText
            }

            MurmurLogger.ui.error("Pipeline: inserting \(transcript.count) chars into target")
            setPhase(.inserting)
            switch await injectText(transcript) {
            case .success:
                MurmurLogger.ui.error("Pipeline: insertion succeeded")
                showTransientPhase(.completed("Done"), audioPath: audioPath, hideAfter: 0.6)
            case .failure(let error):
                MurmurLogger.ui.error("Text insertion failed: \(error.localizedDescription, privacy: .public)")
                showTransientPhase(.failed(error.localizedDescription), audioPath: audioPath, hideAfter: 1.4)
            }
        }
    }

    func cancelDictation() {
        guard phase != .idle else { return }

        processingTask?.cancel()
        processingTask = nil

        let audioPath = audioSession.recordingPath

        if phase == .recording {
            audioSession.stopRecording()
            liveSpeech?.stop()
        }

        showTransientPhase(.cancelled("Cancelled"), audioPath: audioPath, hideAfter: 0.5)
    }

    // MARK: - Private helpers

    private func resolveTranscriptAction(_ transcript: String) async -> TranscriptEditAction {
        guard configManager.editBeforePaste else {
            return .insert(transcript)
        }

        setPhase(.editing)
        capsulePanel.hideCapsule()
        return await transcriptEditPanel.edit(text: transcript)
    }

    private func injectText(_ text: String) async -> Result<Void, Error> {
        let savedIME = IMEService.switchToASCII()
        let savedClipboard = TextInsertionService.saveClipboard()
        let insertedClipboardChangeCount = TextInsertionService.copyToClipboard(text)
        let insertionTarget = textInsertionTarget

        MurmurLogger.ui.error("injectText: target=\(insertionTarget?.displayName ?? "nil", privacy: .public), AX trusted=\(TextInsertionService.isAccessibilityTrusted())")

        do {
            // Step 1: Reactivate the target app first so it has keyboard focus.
            if !TextInsertionService.reactivate(insertionTarget) {
                MurmurLogger.ui.error("injectText: could not reactivate \(insertionTarget?.displayName ?? "target", privacy: .public)")
            }
            try await Task.sleep(nanoseconds: 300_000_000)

            // Step 2: Try to restore focus to the exact text field.
            let focusRestored = TextInsertionService.restoreFocus(to: insertionTarget)
            MurmurLogger.ui.error("injectText: focus restored=\(focusRestored)")
            if focusRestored {
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            // Step 3: Try direct AX insertion (works for native text fields).
            var directInserted = false
            if TextInsertionService.isAccessibilityTrusted() {
                directInserted = (try? TextInsertionService.insertTextDirectly(text, target: insertionTarget)) ?? false
                if !directInserted {
                    directInserted = (try? TextInsertionService.insertTextDirectly(text)) ?? false
                }
            }

            if directInserted {
                MurmurLogger.ui.error("injectText: direct AX insertion succeeded")
            } else {
                // Step 4: Fall back to simulated Cmd+V paste.
                MurmurLogger.ui.error("injectText: using paste simulation")
                try TextInsertionService.simulatePaste()
                try await Task.sleep(nanoseconds: 300_000_000)
            }

            if let saved = savedClipboard {
                _ = TextInsertionService.restoreClipboard(
                    saved,
                    ifChangeCountIs: insertedClipboardChangeCount
                )
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

    private func showTransientPhase(
        _ newPhase: DictationPhase,
        audioPath: String?,
        hideAfter delay: TimeInterval = 1.0
    ) {
        setPhase(newPhase)

        if !capsulePanel.isVisible {
            capsulePanel.showCapsule()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.finish(audioPath: audioPath)
        }
    }

    private func finish(audioPath: String?) {
        capsulePanel.hideCapsule()
        setPhase(.idle)
        processingTask = nil
        textInsertionTarget = nil
        if let audioPath {
            try? FileManager.default.removeItem(atPath: audioPath)
        }
    }
}
