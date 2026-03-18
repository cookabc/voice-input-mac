import AppKit
import ApplicationServices
import Foundation

enum TextInsertionService {
    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func simulatePaste() throws {
        guard AXIsProcessTrusted() else {
            throw TextInsertionError.accessibilityRequired
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            throw TextInsertionError.pasteFailed("Failed to create key event")
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

enum TextInsertionError: LocalizedError {
    case pasteFailed(String)
    case accessibilityRequired

    var errorDescription: String? {
        switch self {
        case .pasteFailed(let message):
            return "Failed to paste: \(message)"
        case .accessibilityRequired:
            return "Copied to clipboard. Grant Accessibility access in System Settings to enable auto-paste."
        }
    }
}