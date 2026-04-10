import AppKit
import SwiftUI

struct NoticePanelAction {
    let title: String
    let role: ButtonRole?
    let handler: @MainActor () -> Void
}

extension NoticePanelAction {
    /// Deep-link to a specific Privacy pane in System Settings.
    static func openPrivacySettings(_ pane: PrivacyPane) -> NoticePanelAction {
        NoticePanelAction(title: String(localized: "Open System Settings"), role: nil) {
            if let url = URL(string: pane.urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Dismiss-only action.
    static func dismiss(title: String = String(localized: "Dismiss")) -> NoticePanelAction {
        NoticePanelAction(title: title, role: .cancel) { }
    }

    enum PrivacyPane {
        case accessibility
        case microphone
        case speechRecognition

        var urlString: String {
            switch self {
            case .accessibility:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case .microphone:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            case .speechRecognition:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
            }
        }
    }
}

enum NoticePanelStyle {
    case info
    case warning

    var tint: Color {
        switch self {
        case .info:
            return MurmurDesignTokens.Colors.accent
        case .warning:
            return MurmurDesignTokens.Colors.warning
        }
    }

    var symbolName: String {
        switch self {
        case .info:
            return "sparkles"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class NoticePanelController: NSObject, NSWindowDelegate {
    private var window: NSPanel?

    func show(
        title: String,
        message: String,
        style: NoticePanelStyle,
        primaryAction: NoticePanelAction,
        secondaryAction: NoticePanelAction? = nil
    ) {
        let contentView = NoticePanelView(
            title: title,
            message: message,
            style: style,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        let panel = NoticePanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 214),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.contentViewController = hostingController
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()

        window?.orderOut(nil)
        window = panel

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        window?.delegate = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private final class NoticePanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct NoticePanelView: View {
    let title: String
    let message: String
    let style: NoticePanelStyle
    let primaryAction: NoticePanelAction
    let secondaryAction: NoticePanelAction?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(style.tint.opacity(0.14))

                    Image(systemName: style.symbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(style.tint)
                }
                .frame(width: MurmurDesignTokens.Panel.noticeIconSize, height: MurmurDesignTokens.Panel.noticeIconSize)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))

                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.noticeDismiss)
                .accessibilityLabel(String(localized: "Dismiss"))
            }

            HStack {
                if let secondaryAction {
                    Button(secondaryAction.title, role: secondaryAction.role) {
                        secondaryAction.handler()
                        onDismiss()
                    }
                    .accessibilityIdentifier(AccessibilityID.noticeSecondaryAction)
                }

                Spacer()

                Button(primaryAction.title, role: primaryAction.role) {
                    primaryAction.handler()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.noticePrimaryAction)
            }
        }
        .padding(MurmurDesignTokens.Panel.noticePadding)
        .frame(width: MurmurDesignTokens.Panel.noticeWidth)
        .panelBackground()
        .padding(MurmurDesignTokens.Spacing.sd)
    }
}