import AppKit
import SwiftUI

// NSPanel with .nonactivatingPanel returns canBecomeKey = false by default,
// blocking all keyboard input to SwiftUI text fields. Override explicitly.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PanelController {
    private let panel: KeyablePanel
    let viewModel = ShellViewModel()

    init() {
        let rootView = ShellPanelView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: rootView)

        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 408, height: 500),
            styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        panel.minSize = NSSize(width: 380, height: 360)
        panel.contentView = hosting
        viewModel.onRequestDismiss = { [weak self] in
            self?.animatedClose()
        }
        viewModel.onRequestQuit = {
            NSApp.terminate(nil)
        }
        viewModel.onRequestFocus = { [weak self] in
            guard let self else { return }
            self.panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func togglePanel(relativeTo button: NSStatusBarButton?) {
        // While recording is active, always show the panel so the user can stop it.
        if viewModel.isRecordingActive {
            showPanel(relativeTo: button)
            return
        }
        if panel.isVisible {
            animatedClose()
        } else {
            showPanel(relativeTo: button)
        }
    }

    func showPanel(relativeTo button: NSStatusBarButton?) {
        positionPanel(relativeTo: button)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        refreshRustStatus()
    }

    private func animatedClose() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            panel.animator().alphaValue = 0
        }) { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        }
    }

    func refreshRustStatus() {
        viewModel.refreshRuntime()
    }

    private func positionPanel(relativeTo button: NSStatusBarButton?) {
        guard let button,
              let buttonWindow = button.window,
              let screenFrame = buttonWindow.screen?.visibleFrame else {
            return
        }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let originX = min(max(screenFrame.minX + 12, buttonFrame.midX - panel.frame.width / 2), screenFrame.maxX - panel.frame.width - 12)
        let originY = buttonFrame.minY - panel.frame.height - 10
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
