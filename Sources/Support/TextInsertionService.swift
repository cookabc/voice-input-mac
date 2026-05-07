import AppKit
import ApplicationServices
import Foundation

// MARK: - Clipboard snapshot

/// Stores all pasteboard items so the clipboard can be restored after pasting.
struct ClipboardSnapshot {
    fileprivate let items: [[NSPasteboard.PasteboardType: Data]]
}

struct TextInsertionTarget {
    let processIdentifier: pid_t
    let displayName: String
    let focusedElement: AXUIElement?
}

enum TextInsertionService {
    // MARK: - Clipboard

    @discardableResult
    static func copyToClipboard(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
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
    @discardableResult
    static func restoreClipboard(_ snapshot: ClipboardSnapshot, ifChangeCountIs expectedChangeCount: Int? = nil) -> Bool {
        let pb = NSPasteboard.general

        if let expectedChangeCount, pb.changeCount != expectedChangeCount {
            return false
        }

        pb.clearContents()
        for entry in snapshot.items {
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            pb.writeObjects([item])
        }

        return true
    }

    // MARK: - Accessibility

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func captureFrontmostTarget() -> TextInsertionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }

        return TextInsertionTarget(
            processIdentifier: app.processIdentifier,
            displayName: app.localizedName ?? app.bundleIdentifier ?? "Unknown App",
            focusedElement: copyFocusedElement()
        )
    }

    @discardableResult
    static func reactivate(_ target: TextInsertionTarget?) -> Bool {
        guard let target else { return true }
        guard let app = NSRunningApplication(processIdentifier: target.processIdentifier) else {
            return false
        }

        return app.activate(options: [.activateAllWindows])
    }

    @discardableResult
    static func restoreFocus(to target: TextInsertionTarget?) -> Bool {
        guard let focusedElement = target?.focusedElement else {
            return false
        }

        if isAttributeSettable(kAXFocusedAttribute as CFString, on: focusedElement),
           AXUIElementSetAttributeValue(
                focusedElement,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
           ) == .success {
            return true
        }

        var windowObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXWindowAttribute as CFString,
            &windowObject
        ) == .success,
        let windowObject,
        CFGetTypeID(windowObject) == AXUIElementGetTypeID() else {
            return false
        }

        let windowElement = unsafeDowncast(windowObject, to: AXUIElement.self)

        if isAttributeSettable(kAXMainAttribute as CFString, on: windowElement) {
            _ = AXUIElementSetAttributeValue(
                windowElement,
                kAXMainAttribute as CFString,
                kCFBooleanTrue
            )
        }

        if isAttributeSettable(kAXFocusedAttribute as CFString, on: windowElement),
           AXUIElementSetAttributeValue(
                windowElement,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
           ) == .success {
            return true
        }

        return false
    }

    @discardableResult
    static func insertTextDirectly(_ text: String, target: TextInsertionTarget? = nil) throws -> Bool {
        guard AXIsProcessTrusted() else {
            throw TextInsertionError.accessibilityRequired
        }

        if let capturedElement = target?.focusedElement,
           insertTextDirectly(text, into: capturedElement) {
            return true
        }

        guard let focusedElement = copyFocusedElement() else {
            return false
        }

        return insertTextDirectly(text, into: focusedElement)
    }

    private static func insertTextDirectly(_ text: String, into focusedElement: AXUIElement) -> Bool {
        guard isAttributeSettable(kAXValueAttribute as CFString, on: focusedElement) else {
            return false
        }

        guard let currentValue = copyStringAttribute(kAXValueAttribute as CFString, from: focusedElement) else {
            return false
        }

        let selectedRange = selectedTextRange(for: focusedElement) ?? CFRange(
            location: currentValue.utf16.count,
            length: 0
        )

        let currentNSString = currentValue as NSString
        let insertionRange = NSRange(location: selectedRange.location, length: selectedRange.length)

        guard insertionRange.location != NSNotFound,
              insertionRange.location + insertionRange.length <= currentNSString.length else {
            return false
        }

        let updatedValue = currentNSString.replacingCharacters(in: insertionRange, with: text)
        guard AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            updatedValue as CFTypeRef
        ) == .success else {
            return false
        }

        // Verify the write actually took effect — Electron/web apps often
        // return .success from AXUIElementSetAttributeValue without applying
        // the change, so we read back and compare.
        if let readBack = copyStringAttribute(kAXValueAttribute as CFString, from: focusedElement),
           readBack == updatedValue {
            // Confirmed — move caret past inserted text.
            if isAttributeSettable(kAXSelectedTextRangeAttribute as CFString, on: focusedElement) {
                var caretRange = CFRange(location: insertionRange.location + text.utf16.count, length: 0)
                if let rangeValue = AXValueCreate(.cfRange, &caretRange) {
                    AXUIElementSetAttributeValue(
                        focusedElement,
                        kAXSelectedTextRangeAttribute as CFString,
                        rangeValue
                    )
                }
            }
            return true
        }

        return false
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

    private static func copyFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        ) == .success,
        let focusedObject,
        CFGetTypeID(focusedObject) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(focusedObject, to: AXUIElement.self)
    }

    private static func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success else {
            return nil
        }

        return rawValue as? String
    }

    private static func selectedTextRange(for element: AXUIElement) -> CFRange? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rawValue
        ) == .success,
        let rawValue,
        CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }

        let rangeValue = unsafeDowncast(rawValue, to: AXValue.self)
        guard AXValueGetType(rangeValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private static func isAttributeSettable(_ attribute: CFString, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute, &settable) == .success else {
            return false
        }

        return settable.boolValue
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
