import SwiftUI

/// App-wide theme preference: System, Light, or Dark.
enum AppTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .light:  String(localized: "Light")
        case .dark:   String(localized: "Dark")
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }

    /// Load persisted preference.
    static func current() -> AppTheme {
        guard let raw = UserDefaults.standard.string(forKey: "appTheme") else { return .system }
        return AppTheme(rawValue: raw) ?? .system
    }

    /// Persist and apply immediately.
    @MainActor
    static func apply(_ theme: AppTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
        NSApp.appearance = theme.appearance
    }
}
