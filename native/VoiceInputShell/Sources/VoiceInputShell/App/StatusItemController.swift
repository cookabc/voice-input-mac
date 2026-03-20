import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panelController = PanelController()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        configureButton()
        observeRecordingState()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Voice Input")
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    private func observeRecordingState() {
        panelController.viewModel.$recordingLine
            .receive(on: RunLoop.main)
            .sink { [weak self] line in
                self?.updateStatusIcon(isRecording: line == "Recording live")
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon(isRecording: Bool) {
        let symbolName = isRecording ? "record.circle.fill" : "waveform.circle.fill"
        let description = isRecording ? "Voice Input — Recording" : "Voice Input"
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
    }

    @objc
    private func handleStatusItemClick(_ sender: AnyObject?) {
        panelController.togglePanel(relativeTo: statusItem.button)
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}
