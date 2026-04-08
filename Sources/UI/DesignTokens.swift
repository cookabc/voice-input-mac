import SwiftUI

enum MurmurDesignTokens {
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
}