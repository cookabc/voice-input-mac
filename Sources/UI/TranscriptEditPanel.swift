import AppKit
import SwiftUI

enum TranscriptEditAction {
    case insert(String)
    case copy(String)
    case cancel
}

@MainActor
final class TranscriptEditPanelController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<TranscriptEditAction, Never>?

    func edit(text: String) async -> TranscriptEditAction {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            showWindow(with: text)
        }
    }

    private func showWindow(with text: String) {
        let contentView = TranscriptEditView(initialText: text) { [weak self] action in
            self?.complete(with: action)
        }

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Review Transcript"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 360))
        window.minSize = NSSize(width: 480, height: 300)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        complete(with: .cancel)
    }

    private func complete(with action: TranscriptEditAction) {
        guard let continuation else { return }
        self.continuation = nil

        if let window {
            window.delegate = nil
            window.orderOut(nil)
            window.close()
            self.window = nil
        }

        continuation.resume(returning: action)
    }
}

private struct TranscriptEditView: View {
    @State private var draft: String

    let onComplete: (TranscriptEditAction) -> Void

    init(initialText: String, onComplete: @escaping (TranscriptEditAction) -> Void) {
        _draft = State(initialValue: initialText)
        self.onComplete = onComplete
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review before inserting")
                    .font(.title3.weight(.semibold))

                Text("Edit the transcript, then insert it, copy it, or cancel.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $draft)
                .font(.system(size: 14))
                .inputFieldStyle()

            HStack {
                Text("Cmd+Return inserts")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    onComplete(.cancel)
                }

                Button("Copy") {
                    onComplete(.copy(trimmedDraft))
                }
                .disabled(trimmedDraft.isEmpty)

                Button("Insert") {
                    onComplete(.insert(trimmedDraft))
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(trimmedDraft.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 300)
    }
}