import SwiftUI

/// Comprehensive design token system for Murmur.
/// Inspired by LuckyTrans's `DesignTokens` — covers all UI panels,
/// not just the capsule HUD.
enum MurmurDesignTokens {

    // MARK: - Colors (macOS semantic + brand)

    enum Colors {
        static let primary = Color(.labelColor)
        static let secondary = Color(.secondaryLabelColor)
        static let tertiary = Color(.tertiaryLabelColor)
        static let surface = Color(.windowBackgroundColor)
        static let controlBackground = Color(.controlBackgroundColor)
        static let separator = Color(.separatorColor)
        static let accent = Color.accentColor
        static let error = Color(red: 1.0, green: 0.72, blue: 0.22)
        static let success = Color(red: 0.30, green: 0.86, blue: 0.56)
    }

    // MARK: - Typography

    enum Typography {
        static let title: Font = .system(size: 17, weight: .semibold, design: .rounded)
        static let headline: Font = .system(size: 15, weight: .semibold, design: .rounded)
        static let body: Font = .system(size: 14, weight: .regular)
        static let detail: Font = .system(size: 13, weight: .medium, design: .rounded)
        static let caption: Font = .system(size: 12, weight: .medium)
        static let monospaced: Font = .system(size: 14, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let sd: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        static let capsule: CGFloat = 32
    }

    // MARK: - Shadows

    enum Shadow {
        static let subtle = Color.black.opacity(0.06)
        static let light = Color.black.opacity(0.12)
        static let medium = Color.black.opacity(0.18)
    }

    // MARK: - Border

    enum Border {
        static let thin: CGFloat = 0.5
        static let regular: CGFloat = 1.0
        static let thick: CGFloat = 1.5
    }

    // MARK: - Opacity

    enum Opacity {
        static let faint: Double = 0.08
        static let subtle: Double = 0.12
        static let light: Double = 0.15
        static let medium: Double = 0.22
        static let strong: Double = 0.5
        static let text: Double = 0.72
    }

    // MARK: - Panel Dimensions

    enum Panel {
        static let noticeWidth: CGFloat = 380
        static let noticePadding: CGFloat = 20
        static let noticeIconSize: CGFloat = 42

        static let transcriptMinWidth: CGFloat = 480
        static let transcriptMinHeight: CGFloat = 300
        static let transcriptPadding: CGFloat = 20

        static let settingsCardCornerRadius: CGFloat = 10
        static let settingsDetailPadding: CGFloat = 24
        static let settingsCardHorizontalPadding: CGFloat = 16
    }

    // MARK: - Icon Sizes

    enum IconSize {
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 18
        static let extraLarge: CGFloat = 24
    }

    // MARK: - Capsule HUD

    enum Capsule {
        static let height: CGFloat = 64
        static let cornerRadius: CGFloat = 32
        static let horizontalPadding: CGFloat = 18
        static let iconSize: CGFloat = 38
        static let outerPaddingX: CGFloat = 12
        static let outerPaddingY: CGFloat = 10
        static let minWidth: CGFloat = 340
        static let maxWidth: CGFloat = 420

        static let recordingTint = Color(red: 1.0, green: 0.30, blue: 0.28)
        static let transcribingTint = Color(red: 0.28, green: 0.64, blue: 1.0)
        static let refiningTint = Color(red: 0.58, green: 0.48, blue: 1.0)
        static let successTint = Color(red: 0.30, green: 0.86, blue: 0.56)
        static let errorTint = Color(red: 1.0, green: 0.72, blue: 0.22)
        static let cancelledTint = Color.secondary
    }

    // MARK: - Animation

    enum Animation {
        static let spring = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.2)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.3)
    }
}