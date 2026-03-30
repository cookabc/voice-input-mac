import AppKit
import SwiftUI

/// Bottom-center floating HUD panel with frosted glass background.
/// Shows waveform bars + live text while dictating.
final class CapsulePanel: NSPanel {

    let viewModel = CapsuleViewModel()
    private var hostingView: NSHostingView<CapsuleView>!

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 56),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        // Frosted glass background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 28
        visualEffect.layer?.masksToBounds = true

        contentView = visualEffect

        hostingView = NSHostingView(rootView: CapsuleView(viewModel: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])
    }

    // MARK: - Show / Hide with animation

    func showCapsule() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let width: CGFloat = 200
        let height: CGFloat = 56
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
            guard let self else { return }
            self.orderOut(nil)
            Task { @MainActor [weak self] in
                self?.viewModel.audioLevel = 0
                self?.viewModel.text = ""
                self?.viewModel.state = .recording
            }
        })
    }

    /// Elastically resize the capsule width based on text content.
    func updateWidth(for text: String) {
        let barAreaWidth: CGFloat = 60
        let padding: CGFloat = 40
        let minWidth: CGFloat = 160
        let maxWidth: CGFloat = 560

        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let newWidth = min(maxWidth, max(minWidth, barAreaWidth + textWidth + padding))

        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - newWidth / 2

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(
                NSRect(x: x, y: self.frame.origin.y, width: newWidth, height: 56),
                display: true
            )
        }
    }

    // Prevent the panel from ever becoming key (would steal focus).
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
