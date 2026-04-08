import AppKit
import SwiftUI

/// Bottom-center floating HUD panel with frosted glass background.
/// Shows waveform bars + live text while dictating.
final class CapsulePanel: NSPanel {

    let viewModel = CapsuleViewModel()
    private var hostingView: NSHostingView<AnyView>!

    private static var totalPanelHeight: CGFloat {
        MurmurDesignTokens.Capsule.height + (MurmurDesignTokens.Capsule.outerPaddingY * 2)
    }

    private static func totalPanelWidth(for capsuleWidth: CGFloat) -> CGFloat {
        capsuleWidth + (MurmurDesignTokens.Capsule.outerPaddingX * 2)
    }

    private var panelHeight: CGFloat { Self.totalPanelHeight }

    private func panelWidth(for capsuleWidth: CGFloat) -> CGFloat { Self.totalPanelWidth(for: capsuleWidth) }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.totalPanelWidth(for: 240), height: Self.totalPanelHeight),
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

        hostingView = NSHostingView(
            rootView: AnyView(
                CapsuleView(viewModel: viewModel)
                    .padding(.horizontal, MurmurDesignTokens.Capsule.outerPaddingX)
                    .padding(.vertical, MurmurDesignTokens.Capsule.outerPaddingY)
            )
        )
        contentView = hostingView
    }

    // MARK: - Show / Hide with animation

    func showCapsule() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let width: CGFloat = max(frame.width > 0 ? self.frame.width : panelWidth(for: 240), panelWidth(for: 240))
        let height: CGFloat = panelHeight
        let x = frame.midX - width / 2
        let y = frame.origin.y + 80 - MurmurDesignTokens.Capsule.outerPaddingY

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
                self.viewModel.phase = .idle
            }
        })
    }

    /// Elastically resize the capsule width based on text content.
    func updateWidth(for text: String, animated: Bool = false) {
        let barAreaWidth: CGFloat = 76
        let padding: CGFloat = 72
        let minWidth: CGFloat = MurmurDesignTokens.Capsule.minWidth
        let maxWidth: CGFloat = MurmurDesignTokens.Capsule.maxWidth

        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let capsuleWidth = min(maxWidth, max(minWidth, barAreaWidth + textWidth + padding))
        let newWidth = panelWidth(for: capsuleWidth)

        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - newWidth / 2

        let newFrame = NSRect(x: x, y: self.frame.origin.y, width: newWidth, height: self.panelHeight)

        guard animated else {
            setFrame(newFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(newFrame, display: true)
        }
    }

    // Prevent the panel from ever becoming key (would steal focus).
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
