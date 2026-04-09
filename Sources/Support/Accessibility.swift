import Foundation

/// Accessibility identifiers for UI testing.
enum AccessibilityID {
    // MARK: - Menu Bar
    static let menuBarLanguagePicker = "menubar_language_picker"
    static let menuBarLLMToggle = "menubar_llm_toggle"
    static let menuBarEditToggle = "menubar_edit_toggle"
    static let menuBarSettings = "menubar_settings"
    static let menuBarQuit = "menubar_quit"
    static let menuBarAccessibilityGrant = "menubar_accessibility_grant"

    // MARK: - Settings
    static let settingsHotkeyField = "settings_hotkey_field"
    static let settingsHotkeyReset = "settings_hotkey_reset"
    static let settingsBaseURL = "settings_base_url"
    static let settingsAPIKey = "settings_api_key"
    static let settingsModel = "settings_model"
    static let settingsTestConnection = "settings_test_connection"
    static let settingsSave = "settings_save"
    static let settingsEditBeforePaste = "settings_edit_before_paste"

    // MARK: - Transcript Edit
    static let transcriptEditor = "transcript_editor"
    static let transcriptCopy = "transcript_copy"
    static let transcriptInsert = "transcript_insert"
    static let transcriptCancel = "transcript_cancel"

    // MARK: - Notice Panel
    static let noticePrimaryAction = "notice_primary_action"
    static let noticeSecondaryAction = "notice_secondary_action"
    static let noticeDismiss = "notice_dismiss"
}
