import Foundation

/// Manages persistent configuration stored in `~/.murmur/config.json`.
/// Provides hot-reload via file-system polling and a fallback to UserDefaults
/// for users who haven't created a config file yet.
@MainActor
final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    struct Config: Codable, Equatable {
        var asrProvider: String?
        var llmBaseURL: String?
        var llmModel: String?
        var llmAPIKey: String?
        var hotkeyModifiers: UInt?
        var hotkeyKeyCode: UInt16?
        var autoPolish: Bool?
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
        static let defaultTTSEnabled = false
        static let defaultAdvancedMode = false
        static let defaultVADEnabled = false
    }

    @Published private(set) var config: Config = Config()
    @Published private(set) var configFilePath: String = ""
    @Published private(set) var isUsingFile: Bool = false

    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    private let configDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.murmur"
    }()

    private var configPath: String { "\(configDir)/config.json" }

    init() {
        configFilePath = configPath
        loadConfig()
        startWatching()
    }

    deinit {
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
    }

    // MARK: - Load / Save

    func loadConfig() {
        let fm = FileManager.default
        if fm.fileExists(atPath: configPath),
           let data = fm.contents(atPath: configPath) {
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                config = try decoder.decode(Config.self, from: data)
                isUsingFile = true
                syncToUserDefaults(config)
                return
            } catch {
                fputs("[ConfigManager] Failed to decode \(configPath): \(error)\n", stderr)
            }
        }

        // Fallback: read from UserDefaults
        config = configFromUserDefaults()
        isUsingFile = false
    }

    func saveConfig(_ newConfig: Config) {
        config = newConfig
        syncToUserDefaults(newConfig)
        writeConfigFile(newConfig)
    }

    /// First-launch migration: writes current UserDefaults values to the JSON file
    /// if the file doesn't already exist.
    func migrateIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configPath) else { return }
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
                self?.loadConfig()
            }
        }
        source.setCancelHandler { [fd = fileDescriptor] in
            close(fd)
        }
        source.resume()
        fileMonitorSource = source
    }

    private func stopWatching() {
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

    private func writeConfigFile(_ cfg: Config) {
        ensureConfigDir()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cfg) else { return }
        FileManager.default.createFile(atPath: configPath, contents: data)
        isUsingFile = true
    }

    private func configFromUserDefaults() -> Config {
        let ud = UserDefaults.standard
        var cfg = Config()
        cfg.llmBaseURL = ud.string(forKey: "llm_polish_base_url")?.trimmingCharacters(in: .whitespaces)
        if let base = cfg.llmBaseURL, !base.isEmpty {
            var cleaned = base
            while cleaned.hasSuffix("/") { cleaned = String(cleaned.dropLast()) }
            if cleaned.hasSuffix("/v1") { cleaned = String(cleaned.dropLast(3)) }
            cfg.llmBaseURL = cleaned
        }
        cfg.llmModel = ud.string(forKey: "llm_polish_model")
        cfg.llmAPIKey = ud.string(forKey: "llm_polish_api_key")
        return cfg
    }

    // MARK: - Property accessors with defaults

    var asrProvider: String { config.asrProvider ?? Config.defaultASRProvider }
    var llmBaseURL: String { config.llmBaseURL ?? Config.defaultLLMBaseURL }
    var llmModel: String { config.llmModel ?? Config.defaultLLMModel }
    var llmAPIKey: String { config.llmAPIKey ?? Config.defaultLLMAPIKey }
    var hotkeyModifiers: UInt { config.hotkeyModifiers ?? Config.defaultHotkeyModifiers }
    var hotkeyKeyCode: UInt16 { config.hotkeyKeyCode ?? Config.defaultHotkeyKeyCode }
    var autoPolish: Bool { config.autoPolish ?? Config.defaultAutoPolish }
    var ttsEnabled: Bool { config.ttsEnabled ?? Config.defaultTTSEnabled }
    var advancedMode: Bool { config.advancedMode ?? Config.defaultAdvancedMode }
    var vadEnabled: Bool { config.vadEnabled ?? Config.defaultVADEnabled }

    private func syncToUserDefaults(_ cfg: Config) {
        let ud = UserDefaults.standard
        ud.set(cfg.llmBaseURL ?? Config.defaultLLMBaseURL, forKey: "llm_polish_base_url")
        ud.set(cfg.llmModel ?? Config.defaultLLMModel, forKey: "llm_polish_model")
        ud.set(cfg.llmAPIKey ?? Config.defaultLLMAPIKey, forKey: "llm_polish_api_key")
    }
}
