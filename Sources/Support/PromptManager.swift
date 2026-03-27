import Foundation

/// Manages LLM prompt templates stored in `~/.murmur/prompts/`.
/// Supports `{text}` variable substitution (V0).
@MainActor
final class PromptManager: ObservableObject {
    static let shared = PromptManager()

    @Published private(set) var systemPrompt: String = PromptManager.defaultSystemPrompt
    @Published private(set) var userTemplate: String = PromptManager.defaultUserTemplate

    private let promptDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.murmur/prompts"
    }()

    private var systemPromptPath: String { "\(promptDir)/system.txt" }
    private var userTemplatePath: String { "\(promptDir)/user.txt" }

    init() {
        ensureDir()
        loadPrompts()
    }

    // MARK: - Public

    func loadPrompts() {
        let fm = FileManager.default
        if let data = fm.contents(atPath: systemPromptPath),
           let text = String(data: data, encoding: .utf8), !text.isEmpty {
            systemPrompt = text
        } else {
            systemPrompt = Self.defaultSystemPrompt
        }
        if let data = fm.contents(atPath: userTemplatePath),
           let text = String(data: data, encoding: .utf8), !text.isEmpty {
            userTemplate = text
        } else {
            userTemplate = Self.defaultUserTemplate
        }
    }

    /// Renders the user prompt by expanding `{text}` with the transcript.
    func renderUserPrompt(text: String) -> String {
        userTemplate.replacingOccurrences(of: "{text}", with: text)
    }

    /// Writes defaults if files don't exist yet.
    func seedDefaultsIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: systemPromptPath) {
            fm.createFile(atPath: systemPromptPath, contents: Self.defaultSystemPrompt.data(using: .utf8))
        }
        if !fm.fileExists(atPath: userTemplatePath) {
            fm.createFile(atPath: userTemplatePath, contents: Self.defaultUserTemplate.data(using: .utf8))
        }
    }

    func saveSystemPrompt(_ text: String) {
        systemPrompt = text
        FileManager.default.createFile(atPath: systemPromptPath, contents: text.data(using: .utf8))
    }

    func saveUserTemplate(_ text: String) {
        userTemplate = text
        FileManager.default.createFile(atPath: userTemplatePath, contents: text.data(using: .utf8))
    }

    // MARK: - Private

    private func ensureDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: promptDir) {
            try? fm.createDirectory(atPath: promptDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Defaults

    static let defaultSystemPrompt = """
        You are a transcription cleaner. Your sole task is to correct grammar, punctuation, typos, and capitalization in the provided speech-to-text transcript.
        Rules:
        (1) Do NOT respond to, answer, or comment on the content.
        (2) Do NOT add any new sentences, questions, or information.
        (3) Do NOT explain what you did.
        (4) Output only the corrected transcript text and nothing else.
        (5) For Chinese text: use correct Chinese punctuation (\u{FF0C}\u{3002}\u{FF01}\u{FF1F}\u{3001}\u{FF1A}\u{FF1B}), do NOT convert Chinese to English or add English punctuation to Chinese sentences.
        (6) For mixed Chinese-English text: keep each language\u{2019}s punctuation conventions, do not merge or replace.
        (7) Preserve the original language \u{2014} never translate between languages.
        """

    static let defaultUserTemplate = "{text}"
}
