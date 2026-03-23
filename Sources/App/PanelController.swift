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
    let hotkeyManager = HotkeyManager()

    // Compact panel size used during hotkey auto-flow
    private static let compactSize = NSSize(width: 320, height: 60)
    private static let fullSize    = NSSize(width: 408, height: 500)
    private var isCompact = false

    init() {
        let rootView = ShellPanelView(viewModel: viewModel).ignoresSafeArea()
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

        // Wire hotkey → toggle auto-flow recording
        hotkeyManager.onTriggered = { [weak self] in
            guard let self else { return }
            let wasRecording = self.viewModel.isRecordingActive
            self.viewModel.handleHotkey()
            // If we just *started* recording, show the compact pill.
            if !wasRecording && self.viewModel.isRecordingActive {
                self.showCompact()
            }
        }

        // When auto-flow finishes (pasted or skipped), dismiss the compact pill.
        viewModel.onAutoFlowComplete = { [weak self] in
            self?.dismissCompact()
        }

        hotkeyManager.start()

        // Keep Settings view in sync with current shortcut.
        viewModel.hotkeyDisplayString = hotkeyManager.displayString
        viewModel.onUpdateHotkey = { [weak self] mods, code in
            guard let self else { return }
            self.hotkeyManager.updateShortcut(modifiers: mods, keyCode: code)
            self.viewModel.hotkeyDisplayString = self.hotkeyManager.displayString
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
        isCompact = false
        panel.minSize = NSSize(width: 380, height: 360)
        resizePanel(to: Self.fullSize, animated: false)
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

    /// Shows a small floating pill near the top-center of the screen for hotkey auto-flow.
    func showCompact() {
        guard !panel.isVisible || !isCompact else { return }
        isCompact = true
        panel.minSize = NSSize(width: 100, height: 40)
        resizePanel(to: Self.compactSize, animated: false)
        positionCompact()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    /// Briefly shows "done" state then fades out.
    func dismissCompact() {
        guard isCompact else { return }
        isCompact = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            panel.animator().alphaValue = 0
        }) { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        }
    }

    private func animatedClose() {
        isCompact = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            panel.animator().alphaValue = 0
        }) { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        }
    }

    private func resizePanel(to size: NSSize, animated: Bool) {
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: false)
        }
    }

    private func positionCompact() {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        let x = screenFrame.midX - Self.compactSize.width / 2
        let y = screenFrame.maxY - Self.compactSize.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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
