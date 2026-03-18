import AppKit
import Foundation

enum TextInsertionService {
    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func pasteToFrontmostApp(_ text: String) throws {
        copyToClipboard(text)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to keystroke \"v\" using command down",
        ]

        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TextInsertionError.pasteFailed(message?.isEmpty == false ? message! : "osascript returned \(process.terminationStatus)")
        }
    }
}

enum TextInsertionError: LocalizedError {
    case pasteFailed(String)

    var errorDescription: String? {
        switch self {
        case .pasteFailed(let message):
            return "Failed to paste transcript: \(message)"
        }
    }
}