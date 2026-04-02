import Foundation

/// Manages persistent configuration stored in `~/Library/Application Support/Murmur/config.json`.
/// Provides hot-reload via file-system polling and a fallback to UserDefaults
/// for users who haven't created a config file yet.
@MainActor
final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    struct Config: Codable, Equatable {
        var version: Int?
        var asrProvider: String?
        var llmBaseURL: String?
        var llmModel: String?
        // Legacy compatibility only. New API keys are stored in Keychain.
        var llmAPIKey: String?
        var hotkeyModifiers: UInt?
        var hotkeyKeyCode: UInt16?
        var autoPolish: Bool?
        var editBeforePaste: Bool?
        var ttsEnabled: Bool?
        var advancedMode: Bool?
        var vadEnabled: Bool?

        // Default values
        static let defaultASRProvider = "coli-sensevoice"
        static let defaultLLMBaseURL = "http://localhost:11434"
        static let defaultLLMModel = "qwen2.5:7b"
        static let defaultLLMAPIKey = ""
        static let defaultHotkeyModifiers: UInt = 0x080000   // ⌥
        static let defaultHotkeyKeyCode: UInt16 = 49          // Space
        static let defaultAutoPolish = true
        static let defaultEditBeforePaste = false
        static let defaultTTSEnabled = false
        static let defaultAdvancedMode = false
        static let defaultVADEnabled = false
        static let currentSchemaVersion = 1
    }

    @Published private(set) var config: Config = Config()
    @Published private(set) var configFilePath: String = ""
    @Published private(set) var isUsingFile: Bool = false

    private static let apiKeyUD = "llm_polish_api_key"
    private static let baseURLUD = "llm_polish_base_url"
    private static let modelUD = "llm_polish_model"
    private static let editBeforePasteUD = "edit_before_paste"

    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var pendingReloadTask: Task<Void, Never>?

    private let configDir = AppPaths.appSupportDirectory.path
    private let legacyConfigPath = AppPaths.legacyConfigFile.path
    private var configPath: String { AppPaths.configFile.path }

    init() {
        configFilePath = configPath
        migrateIfNeeded()
        loadConfig()
        startWatching()
    }

    deinit {
        pendingReloadTask?.cancel()
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
    }

    // MARK: - Load / Save

    func loadConfig() {
        if loadConfigFromFile(at: configPath) {
            configFilePath = configPath
            return
        }

        if loadConfigFromFile(at: legacyConfigPath) {
            configFilePath = legacyConfigPath
            MurmurLogger.app.info("Loaded config from legacy path: \(self.legacyConfigPath, privacy: .public)")
            return
        }

        // Fallback: read from UserDefaults
        config = configFromUserDefaults()
        configFilePath = configPath
        isUsingFile = false
    }

    func saveConfig(_ newConfig: Config) {
        var nextConfig = newConfig
        nextConfig.llmAPIKey = migrateLegacyAPIKeyIfPossible(nextConfig.llmAPIKey, source: "Config save")
        config = nextConfig
        syncToUserDefaults(nextConfig)
        writeConfigFile(nextConfig)
    }

    @discardableResult
    func saveLLMConfiguration(baseURL: String, model: String, apiKey: String) -> Bool {
        let normalizedBaseURL = normalizedBaseURL(from: baseURL)
        let normalizedModel = normalizedModel(from: model)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let apiKeySaved: Bool
        let legacyFallbackAPIKey: String?

        if trimmedAPIKey.isEmpty {
            apiKeySaved = KeychainService.delete(account: KeychainService.llmAPIKeyAccount)
            legacyFallbackAPIKey = nil
        } else if KeychainService.save(trimmedAPIKey, account: KeychainService.llmAPIKeyAccount) {
            apiKeySaved = true
            legacyFallbackAPIKey = nil
            MurmurLogger.app.info("Stored LLM API key in Keychain")
        } else {
            apiKeySaved = false
            legacyFallbackAPIKey = trimmedAPIKey
            MurmurLogger.app.error("Failed to store LLM API key in Keychain; keeping a temporary UserDefaults fallback")
        }

        var nextConfig = config
        nextConfig.llmBaseURL = normalizedBaseURL
        nextConfig.llmModel = normalizedModel
        nextConfig.llmAPIKey = legacyFallbackAPIKey

        config = nextConfig
        syncToUserDefaults(nextConfig)
        writeConfigFile(nextConfig)
        return apiKeySaved || trimmedAPIKey.isEmpty
    }

    func saveEditBeforePaste(_ enabled: Bool) {
        var nextConfig = config
        nextConfig.editBeforePaste = enabled
        config = nextConfig
        syncToUserDefaults(nextConfig)
        writeConfigFile(nextConfig)
    }

    func saveASRProvider(_ provider: String) {
        var nextConfig = config
        nextConfig.asrProvider = provider
        config = nextConfig
        syncToUserDefaults(nextConfig)
        writeConfigFile(nextConfig)
    }

    /// First-launch migration: writes current UserDefaults values to the JSON file
    /// if the file doesn't already exist.
    func migrateIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configPath) else { return }

        ensureConfigDir()

        if fm.fileExists(atPath: legacyConfigPath) {
            do {
                try fm.copyItem(atPath: legacyConfigPath, toPath: configPath)
                applySecureFilePermissions(at: configPath)
                MurmurLogger.app.info("Migrated config from legacy path to \(self.configPath, privacy: .public)")
                return
            } catch {
                MurmurLogger.app.error("Failed to migrate config to Application Support: \(error.localizedDescription, privacy: .public)")
            }
        }

        let current = configFromUserDefaults()
        writeConfigFile(current)
    }

    // MARK: - File Watch (hot-reload)

    private func startWatching() {
        ensureConfigDir()
        // Watch the directory itself (file may not exist yet).
        fileDescriptor = open(configDir, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
        source.setCancelHandler { [fd = fileDescriptor] in
            close(fd)
        }
        source.resume()
        fileMonitorSource = source
    }

    private func stopWatching() {
        pendingReloadTask?.cancel()
        pendingReloadTask = nil
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
    }

    // MARK: - Private Helpers

    private func ensureConfigDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir) {
            try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }
    }

    @discardableResult
    private func loadConfigFromFile(at path: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path),
              let data = fm.contents(atPath: path) else {
            return false
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var decodedConfig = try decoder.decode(Config.self, from: data)
            let needsSchemaRewrite = decodedConfig.version != Config.currentSchemaVersion
            let hadLegacyAPIKey = decodedConfig.llmAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            decodedConfig.llmAPIKey = migrateLegacyAPIKeyIfPossible(decodedConfig.llmAPIKey, source: path)
            decodedConfig.version = Config.currentSchemaVersion

            config = decodedConfig
            isUsingFile = true
            syncToUserDefaults(decodedConfig)

            if path == configPath && (hadLegacyAPIKey && decodedConfig.llmAPIKey == nil || needsSchemaRewrite) {
                writeConfigFile(decodedConfig)
            }

            return true
        } catch {
            MurmurLogger.app.error("Failed to decode config at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func writeConfigFile(_ cfg: Config) {
        ensureConfigDir()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sanitizedConfig(cfg)) else { return }
        let fileURL = URL(fileURLWithPath: configPath)

        do {
            try data.write(to: fileURL, options: .atomic)
            applySecureFilePermissions(at: configPath)
        } catch {
            MurmurLogger.app.error("Failed to write config at \(self.configPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        isUsingFile = true
    }

    private func configFromUserDefaults() -> Config {
        let ud = UserDefaults.standard
        var cfg = Config()
        cfg.version = Config.currentSchemaVersion
        cfg.llmBaseURL = ud.string(forKey: Self.baseURLUD)?.trimmingCharacters(in: .whitespaces)
        if let base = cfg.llmBaseURL, !base.isEmpty {
            var cleaned = base
            while cleaned.hasSuffix("/") { cleaned = String(cleaned.dropLast()) }
            if cleaned.hasSuffix("/v1") { cleaned = String(cleaned.dropLast(3)) }
            cfg.llmBaseURL = cleaned
        }
        cfg.llmModel = ud.string(forKey: Self.modelUD)
        cfg.llmAPIKey = migrateLegacyAPIKeyIfPossible(
            ud.string(forKey: Self.apiKeyUD),
            source: "UserDefaults"
        )
        if ud.object(forKey: Self.editBeforePasteUD) != nil {
            cfg.editBeforePaste = ud.bool(forKey: Self.editBeforePasteUD)
        }
        return cfg
    }

    // MARK: - Property accessors with defaults

    var asrProvider: String { config.asrProvider ?? Config.defaultASRProvider }
    var llmBaseURL: String { config.llmBaseURL ?? Config.defaultLLMBaseURL }
    var llmModel: String { config.llmModel ?? Config.defaultLLMModel }
    var llmAPIKey: String {
        KeychainService.load(account: KeychainService.llmAPIKeyAccount)
            ?? config.llmAPIKey
            ?? Config.defaultLLMAPIKey
    }
    var hotkeyModifiers: UInt { config.hotkeyModifiers ?? Config.defaultHotkeyModifiers }
    var hotkeyKeyCode: UInt16 { config.hotkeyKeyCode ?? Config.defaultHotkeyKeyCode }
    var autoPolish: Bool { config.autoPolish ?? Config.defaultAutoPolish }
    var editBeforePaste: Bool { config.editBeforePaste ?? Config.defaultEditBeforePaste }
    var ttsEnabled: Bool { config.ttsEnabled ?? Config.defaultTTSEnabled }
    var advancedMode: Bool { config.advancedMode ?? Config.defaultAdvancedMode }
    var vadEnabled: Bool { config.vadEnabled ?? Config.defaultVADEnabled }

    private func syncToUserDefaults(_ cfg: Config) {
        let ud = UserDefaults.standard
        ud.set(cfg.llmBaseURL ?? Config.defaultLLMBaseURL, forKey: Self.baseURLUD)
        ud.set(cfg.llmModel ?? Config.defaultLLMModel, forKey: Self.modelUD)

        if let legacyAPIKey = cfg.llmAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines), !legacyAPIKey.isEmpty {
            ud.set(legacyAPIKey, forKey: Self.apiKeyUD)
        } else {
            ud.removeObject(forKey: Self.apiKeyUD)
        }

        ud.set(cfg.editBeforePaste ?? Config.defaultEditBeforePaste, forKey: Self.editBeforePasteUD)
    }

    private func sanitizedConfig(_ cfg: Config) -> Config {
        var sanitized = cfg
        sanitized.version = Config.currentSchemaVersion
        sanitized.llmAPIKey = nil
        return sanitized
    }

    private func scheduleReload() {
        pendingReloadTask?.cancel()
        pendingReloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.loadConfig()
        }
    }

    private func applySecureFilePermissions(at path: String) {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: path
            )
        } catch {
            MurmurLogger.app.error("Failed to apply secure permissions to \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func normalizedBaseURL(from rawValue: String) -> String {
        var normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") { normalized = String(normalized.dropLast()) }
        if normalized.hasSuffix("/v1") { normalized = String(normalized.dropLast(3)) }
        return normalized.isEmpty ? Config.defaultLLMBaseURL : normalized
    }

    private func normalizedModel(from rawValue: String) -> String {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? Config.defaultLLMModel : normalized
    }

    private func migrateLegacyAPIKeyIfPossible(_ rawValue: String?, source: String) -> String? {
        guard let legacyValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !legacyValue.isEmpty else {
            return nil
        }

        if KeychainService.load(account: KeychainService.llmAPIKeyAccount) != nil {
            UserDefaults.standard.removeObject(forKey: Self.apiKeyUD)
            return nil
        }

        guard KeychainService.save(legacyValue, account: KeychainService.llmAPIKeyAccount) else {
            MurmurLogger.app.error("Failed to migrate LLM API key from \(source, privacy: .public) to Keychain")
            return legacyValue
        }

        UserDefaults.standard.removeObject(forKey: Self.apiKeyUD)
        MurmurLogger.app.info("Migrated LLM API key from \(source, privacy: .public) to Keychain")
        return nil
    }
}
