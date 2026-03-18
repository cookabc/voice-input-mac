import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private let panel: NSPanel
    private let viewModel = ShellViewModel()

    init() {
        let rootView = ShellPanelView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: rootView)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 408, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = hosting
        viewModel.onRequestDismiss = { [weak panel] in
            panel?.orderOut(nil)
        }
    }

    func togglePanel(relativeTo button: NSStatusBarButton?) {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel(relativeTo: button)
        }
    }

    func showPanel(relativeTo button: NSStatusBarButton?) {
        positionPanel(relativeTo: button)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshRustStatus()
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
