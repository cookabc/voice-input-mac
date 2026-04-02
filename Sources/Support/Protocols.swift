import Foundation

@MainActor
protocol ConfigManaging: AnyObject {
    var asrProvider: String { get }
    var editBeforePaste: Bool { get }

    func migrateIfNeeded()

    @discardableResult
    func saveLLMConfiguration(baseURL: String, model: String, apiKey: String) -> Bool

    func saveEditBeforePaste(_ enabled: Bool)
}

@MainActor
protocol PromptManaging: AnyObject {
    var systemPrompt: String { get }

    func renderUserPrompt(text: String) -> String
    func seedDefaultsIfNeeded()
}

extension ConfigManager: ConfigManaging {}
extension PromptManager: PromptManaging {}