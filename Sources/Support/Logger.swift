import Foundation
import os

enum MurmurLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.murmur.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let speech = Logger(subsystem: subsystem, category: "speech")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let network = Logger(subsystem: subsystem, category: "network")
}