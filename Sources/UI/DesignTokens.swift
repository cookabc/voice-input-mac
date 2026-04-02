import SwiftUI

enum MurmurDesignTokens {
    enum Capsule {
        static let height: CGFloat = 64
        static let cornerRadius: CGFloat = 32
        static let horizontalPadding: CGFloat = 18
        static let iconSize: CGFloat = 38

        static let recordingTint = Color(red: 0.98, green: 0.36, blue: 0.33)
        static let transcribingTint = Color(red: 0.34, green: 0.67, blue: 0.97)
        static let refiningTint = Color(red: 0.63, green: 0.56, blue: 0.96)
        static let successTint = Color(red: 0.41, green: 0.84, blue: 0.58)
        static let errorTint = Color(red: 0.98, green: 0.76, blue: 0.27)
        static let cancelledTint = Color.secondary

        static let shadowColor = Color.black.opacity(0.18)
        static let borderColor = Color.white.opacity(0.18)
    }
}