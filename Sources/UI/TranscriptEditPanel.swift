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
        window.title = String(localized: "Review Transcript")
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
    @State private var copied = false

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
                Text(String(localized: "Review before inserting"))
                    .font(.title3.weight(.semibold))

                Text(String(localized: "Edit the transcript, then insert it, copy it, or cancel."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $draft)
                .font(.system(size: 14))
                .inputFieldStyle()
                .accessibilityIdentifier(AccessibilityID.transcriptEditor)

            HStack {
                Text(String(localized: "Cmd+Return inserts"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(String(localized: "Cancel")) {
                    onComplete(.cancel)
                }
                .accessibilityIdentifier(AccessibilityID.transcriptCancel)

                Button {
                    guard !copied else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        onComplete(.copy(trimmedDraft))
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                        Text(copied ? String(localized: "Copied") : String(localized: "Copy"))
                    }
                    .foregroundStyle(copied ? .green : .primary)
                }
                .disabled(trimmedDraft.isEmpty)
                .accessibilityIdentifier(AccessibilityID.transcriptCopy)

                Button(String(localized: "Insert")) {
                    onComplete(.insert(trimmedDraft))
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(trimmedDraft.isEmpty)
                .accessibilityIdentifier(AccessibilityID.transcriptInsert)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 300)
    }
}