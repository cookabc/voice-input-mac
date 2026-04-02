import Foundation

enum DictionaryManager {
    /// Path: ~/Library/Application Support/Murmur/dictionary.txt
    static var dictionaryFilePath: String {
        AppPaths.dictionaryFile.path
    }

    /// Creates the standard Murmur support directory and dictionary.txt if missing.
    static func ensureFileExists() {
        let fm = FileManager.default
        let dir = AppPaths.appSupportDirectory.path
        let path = dictionaryFilePath

        migrateIfNeeded(fileManager: fm)

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

    private static func migrateIfNeeded(fileManager: FileManager) {
        let newPath = dictionaryFilePath
        let legacyPath = AppPaths.legacyDictionaryFile.path

        guard !fileManager.fileExists(atPath: newPath), fileManager.fileExists(atPath: legacyPath) else { return }

        do {
            if !fileManager.fileExists(atPath: AppPaths.appSupportDirectory.path) {
                try fileManager.createDirectory(at: AppPaths.appSupportDirectory, withIntermediateDirectories: true)
            }
            try fileManager.copyItem(atPath: legacyPath, toPath: newPath)
            MurmurLogger.app.info("Migrated dictionary file to \(newPath, privacy: .public)")
        } catch {
            MurmurLogger.app.error("Failed to migrate dictionary file from \(legacyPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
