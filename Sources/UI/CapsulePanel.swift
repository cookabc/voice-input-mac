import AppKit
import SwiftUI

/// Bottom-center floating HUD panel with frosted glass background.
/// Shows waveform bars + live text while dictating.
final class CapsulePanel: NSPanel {

    let viewModel = CapsuleViewModel()
    private var hostingView: NSHostingView<CapsuleView>!

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: MurmurDesignTokens.Capsule.height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        hostingView = NSHostingView(rootView: CapsuleView(viewModel: viewModel))
        contentView = hostingView
    }

    // MARK: - Show / Hide with animation

    func showCapsule() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let width: CGFloat = max(frame.width > 0 ? self.frame.width : 240, 240)
        let height: CGFloat = MurmurDesignTokens.Capsule.height
        let x = frame.midX - width / 2
        let y = frame.origin.y + 80

        // Start below and transparent
        setFrame(NSRect(x: x, y: y - 20, width: width, height: height), display: false)
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
            self.animator().setFrame(
                NSRect(x: x, y: y, width: width, height: height),
                display: true
            )
        }
    }

    func hideCapsule() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
            self.animator().setFrame(
                NSRect(x: frame.origin.x, y: frame.origin.y - 10,
                       width: frame.width, height: frame.height),
                display: true
            )
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.orderOut(nil)
                self.viewModel.audioLevel = 0
                self.viewModel.text = ""
                self.viewModel.state = .recording
            }
        })
    }

    /// Elastically resize the capsule width based on text content.
    func updateWidth(for text: String) {
        let barAreaWidth: CGFloat = 76
        let padding: CGFloat = 72
        let minWidth: CGFloat = 220
        let maxWidth: CGFloat = 560

        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let newWidth = min(maxWidth, max(minWidth, barAreaWidth + textWidth + padding))

        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - newWidth / 2

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(
                NSRect(x: x, y: self.frame.origin.y, width: newWidth, height: MurmurDesignTokens.Capsule.height),
                display: true
            )
        }
    }

    // Prevent the panel from ever becoming key (would steal focus).
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
