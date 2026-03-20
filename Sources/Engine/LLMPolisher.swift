import Foundation

enum LLMPolisherError: Error, LocalizedError {
    case noApiKey
    case httpError(Int, String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No API key saved. Click ✦ Polish and enter your OpenAI API key."
        case .httpError(let code, let body):
            return "LLM API error \(code): \(body.isEmpty ? "unknown" : body)"
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
        let v = url.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(v.isEmpty ? "https://api.openai.com" : v, forKey: Self.baseURLUD)
    }

    nonisolated func saveModel(_ m: String) {
        let v = m.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(v.isEmpty ? "gpt-4o-mini" : v, forKey: Self.modelUD)
    }

    func polish(text: String) async throws -> String {
        guard let key = apiKey else { throw LLMPolisherError.noApiKey }

        let baseURL = UserDefaults.standard.string(forKey: Self.baseURLUD) ?? "https://api.openai.com"
        let model   = UserDefaults.standard.string(forKey: Self.modelUD)   ?? "gpt-4o-mini"

        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw LLMPolisherError.unexpectedResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role":    "system",
                    "content": "You are a transcription editor. Fix grammar, punctuation, and clarity of the spoken text while preserving the original meaning and tone. Return only the polished text with no explanations or extra commentary."
                ],
                ["role": "user", "content": text]
            ],
            "max_tokens": 1024,
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw LLMPolisherError.httpError(http.statusCode, body)
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
