import Foundation

enum DictionaryManager {
    /// Path: ~/.murmur/dictionary.txt
    static var dictionaryFilePath: String {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".murmur")
        return (dir as NSString).appendingPathComponent("dictionary.txt")
    }

    /// Creates ~/.murmur/ and dictionary.txt with starter comments if missing.
    static func ensureFileExists() {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".murmur")
        let path = (dir as NSString).appendingPathComponent("dictionary.txt")
        let fm = FileManager.default

        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        guard !fm.fileExists(atPath: path) else { return }

        let starter = """
        # Murmur User Dictionary
        # One term per line. Lines starting with # are ignored.
        # These terms are used to improve transcription polish accuracy.
        #
        # Examples:
        #   SwiftUI
        #   Kubernetes
        #   gRPC
        #   ChatGPT
        """
        try? starter.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Reads and returns non-empty, non-comment entries from the dictionary file.
    static func loadEntries() -> [String] {
        guard let contents = try? String(contentsOfFile: dictionaryFilePath, encoding: .utf8) else {
            return []
        }
        return contents
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
