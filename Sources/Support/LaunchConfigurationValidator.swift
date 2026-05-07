import Foundation

enum LaunchConfigurationIssue {
    case unbundledExecutable
    case missingUsageDescriptions([String])

    var logMessage: String {
        switch self {
        case .unbundledExecutable:
            return "Murmur must be launched from an app bundle with privacy usage descriptions"
        case .missingUsageDescriptions(let keys):
            return "Murmur is missing required privacy usage descriptions: \(keys.joined(separator: ", "))"
        }
    }

    var alertTitle: String {
        switch self {
        case .unbundledExecutable:
            return "Murmur 启动方式不正确"
        case .missingUsageDescriptions:
            return "Murmur 缺少权限声明"
        }
    }

    var alertMessage: String {
        switch self {
        case .unbundledExecutable:
            return "当前启动的是裸可执行文件，macOS 不会提供麦克风和语音识别的权限说明，因此系统会直接终止进程。\n\n开发环境请使用 ./dev.sh，或者直接打开 .stage/Murmur.app。"
        case .missingUsageDescriptions(let keys):
            return "当前 App bundle 缺少以下 Info.plist 权限说明：\n\(keys.joined(separator: "\n"))\n\n请重新生成或修复 Murmur.app 后再启动。"
        }
    }
}

enum LaunchConfigurationValidator {
    private static let requiredUsageDescriptionKeys = [
        "NSMicrophoneUsageDescription",
        "NSSpeechRecognitionUsageDescription"
    ]

    static func validate(bundle: Bundle = .main) -> LaunchConfigurationIssue? {
        guard bundle.bundleURL.pathExtension == "app" else {
            return .unbundledExecutable
        }

        let missingKeys = requiredUsageDescriptionKeys.filter { key in
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
                return true
            }

            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard missingKeys.isEmpty else {
            return .missingUsageDescriptions(missingKeys)
        }

        return nil
    }
}
