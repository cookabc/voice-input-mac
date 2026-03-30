import AppKit
import ApplicationServices
import Foundation

// MARK: - Clipboard snapshot

/// Stores all pasteboard items so the clipboard can be restored after pasting.
struct ClipboardSnapshot {
    fileprivate let items: [[NSPasteboard.PasteboardType: Data]]
}

enum TextInsertionService {

    // MARK: - Clipboard

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Saves a snapshot of the current general pasteboard contents.
    static func saveClipboard() -> ClipboardSnapshot? {
        let pb = NSPasteboard.general
        guard let items = pb.pasteboardItems, !items.isEmpty else { return nil }
        var snapshot: [[NSPasteboard.PasteboardType: Data]] = []
        for item in items {
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            if !entry.isEmpty { snapshot.append(entry) }
        }
        return snapshot.isEmpty ? nil : ClipboardSnapshot(items: snapshot)
    }

    /// Restores a previously-saved clipboard snapshot.
    static func restoreClipboard(_ snapshot: ClipboardSnapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        for entry in snapshot.items {
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            pb.writeObjects([item])
        }
    }

    // MARK: - Accessibility

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Paste simulation

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