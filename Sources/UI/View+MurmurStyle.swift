import SwiftUI

// MARK: - Reusable glass / panel modifiers

/// Extracted from hardcoded styling in NoticePanel, TranscriptEditPanel, and
/// SettingsWindowController. Cross-pollinated from LuckyTrans's shared modifier pattern.

extension View {
    /// Glass panel background — `regularMaterial` with a rounded stroke and drop shadow.
    /// Used by NoticePanel and similar floating panels.
    /// Falls back to a solid background when Reduce Transparency is enabled.
    func panelBackground(
        cornerRadius: CGFloat = MurmurDesignTokens.Radius.large + 6,
        strokeOpacity: Double = MurmurDesignTokens.Opacity.medium
    ) -> some View {
        self.modifier(PanelBackgroundModifier(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
    }

    /// Settings card style — `controlBackgroundColor` background with a thin border.
    func settingsCard(
        cornerRadius: CGFloat = MurmurDesignTokens.Panel.settingsCardCornerRadius
    ) -> some View {
        self
            .background(
                MurmurDesignTokens.Colors.controlBackground,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(MurmurDesignTokens.Opacity.faint - 0.02), lineWidth: MurmurDesignTokens.Border.thin)
            )
    }

    /// Text editor / input field overlay — thin secondary border.
    func inputFieldStyle(
        cornerRadius: CGFloat = MurmurDesignTokens.Radius.medium
    ) -> some View {
        self
            .padding(MurmurDesignTokens.Spacing.sd)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.secondary.opacity(MurmurDesignTokens.Opacity.light), lineWidth: MurmurDesignTokens.Border.regular)
            }
    }

    /// Conditional modifier — apply a transform only when a condition is true.
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

private struct PanelBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    let strokeOpacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(strokeOpacity), lineWidth: MurmurDesignTokens.Border.regular)
                    )
            }
            .shadow(color: MurmurDesignTokens.Shadow.medium, radius: 16, y: 8)
    }
}
