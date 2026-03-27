import Foundation

/// Manages persistent configuration stored in `~/.murmur/config.json`.
/// Provides hot-reload via file-system polling and a fallback to UserDefaults
/// for users who haven't created a config file yet.
@MainActor
final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    struct Config: Codable, Equatable {
        var asrProvider: String = "coli"
        var llmBaseURL: String = "http://localhost:11434"
        var llmModel: String = "qwen2.5:7b"
        var llmAPIKey: String = ""
        var hotkeyModifiers: UInt = 0x080000   // ⌥
        var hotkeyKeyCode: UInt16 = 49          // Space
        var autoPolish: Bool = true
        var ttsEnabled: Bool = false
        var advancedMode: Bool = false
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
        if let url = ud.string(forKey: "llm_polish_base_url"), !url.isEmpty {
            var base = url.trimmingCharacters(in: .whitespaces)
            while base.hasSuffix("/") { base = String(base.dropLast()) }
            if base.hasSuffix("/v1") { base = String(base.dropLast(3)) }
            cfg.llmBaseURL = base
        }
        if let model = ud.string(forKey: "llm_polish_model"), !model.isEmpty {
            cfg.llmModel = model
        }
        if let key = ud.string(forKey: "llm_polish_api_key"), !key.isEmpty {
            cfg.llmAPIKey = key
        }
        return cfg
    }

    private func syncToUserDefaults(_ cfg: Config) {
        let ud = UserDefaults.standard
        ud.set(cfg.llmBaseURL, forKey: "llm_polish_base_url")
        ud.set(cfg.llmModel, forKey: "llm_polish_model")
        ud.set(cfg.llmAPIKey, forKey: "llm_polish_api_key")
    }
}
