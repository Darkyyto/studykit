import Foundation

enum SandboxMigration {
    private static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "dev.focuskit.FocusKit"
    private static let importedKey = "importedSandboxDefaults"

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static var container: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Containers/\(bundleIdentifier)/Data/Library", directoryHint: .isDirectory)
    }

    static var libraryRoot: URL {
        let legacy = container.appending(path: "Application Support/FocusKit", directoryHint: .isDirectory)
        if !isSandboxed, FileManager.default.fileExists(atPath: legacy.path(percentEncoded: false)) {
            return legacy
        }
        return URL.applicationSupportDirectory.appending(path: "FocusKit", directoryHint: .isDirectory)
    }

    static func importDefaults() {
        let defaults = UserDefaults.standard
        guard !isSandboxed, !defaults.bool(forKey: importedKey) else { return }
        let plist = container.appending(path: "Preferences/\(bundleIdentifier).plist")
        if let values = NSDictionary(contentsOf: plist) as? [String: Any] {
            for (key, value) in values where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: importedKey)
    }
}
