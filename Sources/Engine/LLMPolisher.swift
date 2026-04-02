import Foundation

enum LLMPolisherError: Error, LocalizedError {
    case noApiKey
    case httpError(Int, String, String)  // code, body, url
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No API key saved. Open Settings to enter your API key, or use a local endpoint that does not require one."
        case .httpError(let code, _, _):
            switch code {
            case 401:
                return "API key invalid or expired (HTTP 401). Check your key in Settings."
            case 403:
                return "Access denied (HTTP 403). Your API key may lack permission for this model."
            case 429:
                return "Rate limited (HTTP 429). Wait a moment and try again."
            case 500...599:
                return "Server error (HTTP \(code)). The API endpoint may be temporarily unavailable."
            default:
                return "LLM request failed (HTTP \(code)). Check your Base URL and model in Settings."
            }
        case .unexpectedResponse:
            return "Unexpected response from LLM API."
        }
    }
}

actor LLMPolisher {
    static let shared = LLMPolisher()

    struct RuntimeProbe {
        let line: String
        let isReady: Bool
        let actionHint: String?
    }

    private static let apiKeyUD   = "llm_polish_api_key"
    private static let baseURLUD  = "llm_polish_base_url"
    private static let modelUD    = "llm_polish_model"
    private static let apiKeyAccount = KeychainService.llmAPIKeyAccount

    nonisolated var apiKey: String? {
        if let key = KeychainService.load(account: Self.apiKeyAccount) {
            return key
        }

        let defaults = UserDefaults.standard
        guard let legacyValue = defaults.string(forKey: Self.apiKeyUD)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !legacyValue.isEmpty else {
            return nil
        }

        if KeychainService.save(legacyValue, account: Self.apiKeyAccount) {
            defaults.removeObject(forKey: Self.apiKeyUD)
        }

        return legacyValue
    }

    nonisolated var baseURL: String {
        UserDefaults.standard.string(forKey: Self.baseURLUD) ?? "https://api.openai.com"
    }

    nonisolated var normalizedBaseURL: String {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        if base.hasSuffix("/v1") { base = String(base.dropLast(3)) }
        return base.isEmpty ? "https://api.openai.com" : base
    }

    nonisolated var requiresAPIKey: Bool {
        guard let url = URL(string: normalizedBaseURL), let host = url.host?.lowercased() else {
            return true
        }

        return !(host == "localhost" || host == "127.0.0.1" || host == "::1")
    }

    nonisolated var model: String {
        UserDefaults.standard.string(forKey: Self.modelUD) ?? "gpt-4o-mini"
    }

    nonisolated var configuredModel: String {
        let m = model.trimmingCharacters(in: .whitespaces)
        return m.isEmpty ? "gpt-4o-mini" : m
    }

    @discardableResult
    nonisolated func saveApiKey(_ key: String) -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaults = UserDefaults.standard

        if trimmedKey.isEmpty {
            defaults.removeObject(forKey: Self.apiKeyUD)
            return KeychainService.delete(account: Self.apiKeyAccount)
        }

        guard KeychainService.save(trimmedKey, account: Self.apiKeyAccount) else {
            MurmurLogger.network.error("Failed to save API key to Keychain")
            defaults.set(trimmedKey, forKey: Self.apiKeyUD)
            return false
        }

        defaults.removeObject(forKey: Self.apiKeyUD)
        return true
    }

    nonisolated func saveBaseURL(_ url: String) {
        var v = url.trimmingCharacters(in: .whitespaces)
        while v.hasSuffix("/") { v = String(v.dropLast()) }
        // Strip trailing /v1 so we always append it ourselves.
        if v.hasSuffix("/v1") { v = String(v.dropLast(3)) }
        UserDefaults.standard.set(v.isEmpty ? "https://api.openai.com" : v, forKey: Self.baseURLUD)
    }

    nonisolated func saveModel(_ m: String) {
        let v = m.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(v.isEmpty ? "gpt-4o-mini" : v, forKey: Self.modelUD)
    }

    func runtimeProbe() async -> RuntimeProbe {
        if requiresAPIKey {
            return RuntimeProbe(
                line: "Remote endpoint configured · API key required",
                isReady: apiKey != nil,
                actionHint: apiKey == nil ? "Enter API key in Settings." : nil
            )
        }

        guard let url = URL(string: "\(normalizedBaseURL)/api/tags") else {
            return RuntimeProbe(
                line: "Local endpoint URL invalid",
                isReady: false,
                actionHint: "Use a valid localhost base URL, e.g. http://localhost:11434"
            )
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return RuntimeProbe(
                    line: "Local model server unreachable",
                    isReady: false,
                    actionHint: "Start Ollama and ensure it is listening on localhost."
                )
            }

            struct TagResponse: Decodable {
                struct Model: Decodable { let name: String }
                let models: [Model]
            }

            let decoded = try JSONDecoder().decode(TagResponse.self, from: data)
            let names = Set(decoded.models.map { $0.name })
            let target = configuredModel
            let hasModel = names.contains(target) || names.contains(where: { $0.hasPrefix("\(target):") })

            if hasModel {
                return RuntimeProbe(
                    line: "Local runtime ready · model: \(target)",
                    isReady: true,
                    actionHint: nil
                )
            }

            return RuntimeProbe(
                line: "Local runtime ready · model missing: \(target)",
                isReady: false,
                actionHint: "Run: ollama pull \(target)"
            )
        } catch {
            return RuntimeProbe(
                line: "Local model server unreachable",
                isReady: false,
                actionHint: "Install/start Ollama and retry."
            )
        }
    }

    func polish(text: String, dictionary: [String] = []) async throws -> String {
        let key = apiKey
        if requiresAPIKey && key == nil {
            throw LLMPolisherError.noApiKey
        }

        let base = normalizedBaseURL
        let model   = configuredModel

        let endpointURL = "\(base)/v1/chat/completions"
        MurmurLogger.network.info("POST \(endpointURL, privacy: .public) model=\(model, privacy: .public)")

        guard let url = URL(string: endpointURL) else {
            throw LLMPolisherError.unexpectedResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let key, requiresAPIKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (baseSystemPrompt, userContent) = await MainActor.run {
            let pm = PromptManager.shared
            return (pm.systemPrompt, pm.renderUserPrompt(text: text))
        }

        let systemPrompt: String
        if dictionary.isEmpty {
            systemPrompt = baseSystemPrompt
        } else {
            let terms = dictionary.prefix(200).joined(separator: ", ")
            systemPrompt = baseSystemPrompt + " When correcting spelling and capitalization, prefer these domain-specific terms: " + terms + "."
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userContent]
            ],
            "max_tokens": 1024,
            "temperature": 0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            MurmurLogger.network.error("HTTP \(http.statusCode) from \(url.absoluteString, privacy: .public): \(body, privacy: .public)")
            throw LLMPolisherError.httpError(http.statusCode, body, url.absoluteString)
        }

        struct Message:    Decodable { let content: String }
        struct Choice:     Decodable { let message: Message }
        struct Completion: Decodable { let choices: [Choice] }

        let completion = try JSONDecoder().decode(Completion.self, from: data)
        guard let content = completion.choices.first?.message.content else {
            throw LLMPolisherError.unexpectedResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
