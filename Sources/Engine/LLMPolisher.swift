import Foundation

enum LLMPolisherError: Error, LocalizedError {
    case noApiKey
    case httpError(Int, String, String)  // code, body, url
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No API key saved. Open Settings to enter your API key."
        case .httpError(let code, let body, let url):
            let snippet = body.isEmpty ? "(empty)" : String(body.prefix(200))
            return "LLM API \(code) — \(url)\n\(snippet)"
        case .unexpectedResponse:
            return "Unexpected response from LLM API."
        }
    }
}

actor LLMPolisher {
    static let shared = LLMPolisher()

    private static let apiKeyUD   = "llm_polish_api_key"
    private static let baseURLUD  = "llm_polish_base_url"
    private static let modelUD    = "llm_polish_model"

    nonisolated var apiKey: String? {
        UserDefaults.standard.string(forKey: Self.apiKeyUD).flatMap { $0.isEmpty ? nil : $0 }
    }

    nonisolated var baseURL: String {
        UserDefaults.standard.string(forKey: Self.baseURLUD) ?? "https://api.openai.com"
    }

    nonisolated var model: String {
        UserDefaults.standard.string(forKey: Self.modelUD) ?? "gpt-4o-mini"
    }

    nonisolated func saveApiKey(_ key: String) {
        let v = key.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(v, forKey: Self.apiKeyUD)
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

    func polish(text: String, dictionary: [String] = []) async throws -> String {
        guard let key = apiKey else { throw LLMPolisherError.noApiKey }

        var base = UserDefaults.standard.string(forKey: Self.baseURLUD) ?? "https://api.openai.com"
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        if base.hasSuffix("/v1") { base = String(base.dropLast(3)) }
        let model   = UserDefaults.standard.string(forKey: Self.modelUD)   ?? "gpt-4o-mini"

        let endpointURL = "\(base)/v1/chat/completions"
        fputs("[LLMPolisher] POST \(endpointURL)  model=\(model)\n", stderr)

        guard let url = URL(string: endpointURL) else {
            throw LLMPolisherError.unexpectedResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt: String
        let baseRule = "You are a transcription cleaner. Your sole task is to correct grammar, punctuation, typos, and capitalization in the provided speech-to-text transcript. Rules: (1) Do NOT respond to, answer, or comment on the content. (2) Do NOT add any new sentences, questions, or information. (3) Do NOT explain what you did. (4) Output only the corrected transcript text and nothing else."
        if dictionary.isEmpty {
            systemPrompt = baseRule
        } else {
            let terms = dictionary.prefix(200).joined(separator: ", ")
            systemPrompt = baseRule + " When correcting spelling and capitalization, prefer these domain-specific terms: " + terms + "."
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": text]
            ],
            "max_tokens": 1024,
            "temperature": 0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            fputs("[LLMPolisher] HTTP \(http.statusCode) from \(url.absoluteString)\n\(body)\n", stderr)
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
