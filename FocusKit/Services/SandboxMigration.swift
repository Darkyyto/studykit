import Foundation

enum SandboxMigration {
    private static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "dev.focuskit.FocusKit"
    private static let importedKey = "importedSandboxDefaults"

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static let legacyIdentifiers = ["dev.focuskit.FocusKit"]
    private static let legacyFolders = ["FocusKit"]
    private static let importedLegacyKey = "importedLegacyDefaults"

    private static var dataFolder: String {
        Bundle.main.object(forInfoDictionaryKey: "FocusKitDataFolder") as? String ?? "FocusKit"
    }

    private static var container: URL {
        container(for: bundleIdentifier)
    }

    private static func container(for identifier: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Containers/\(identifier)/Data/Library", directoryHint: .isDirectory)
    }

    static let libraryRoot: URL = resolveRoot()

    private static func resolveRoot() -> URL {
        let manager = FileManager.default
        let contained = container.appending(path: "Application Support/\(dataFolder)", directoryHint: .isDirectory)
        let root = !isSandboxed && manager.fileExists(atPath: contained.path(percentEncoded: false))
            ? contained
            : URL.applicationSupportDirectory.appending(path: dataFolder, directoryHint: .isDirectory)
        guard !isSandboxed, !manager.fileExists(atPath: root.appending(path: "Library.json").path(percentEncoded: false)) else { return root }
        for candidate in legacyRoots where candidate.standardizedFileURL.path != root.standardizedFileURL.path {
            guard manager.fileExists(atPath: candidate.appending(path: "Library.json").path(percentEncoded: false)) else { continue }
            merge(candidate, into: root)
            break
        }
        return root
    }

    private static var legacyRoots: [URL] {
        legacyIdentifiers.flatMap { identifier in
            legacyFolders.map { container(for: identifier).appending(path: "Application Support/\($0)", directoryHint: .isDirectory) }
        } + legacyFolders.map { URL.applicationSupportDirectory.appending(path: $0, directoryHint: .isDirectory) }
    }

    private static func merge(_ source: URL, into destination: URL) {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: destination.path(percentEncoded: false), isDirectory: &isDirectory) else {
            try? manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.copyItem(at: source, to: destination)
            return
        }
        guard isDirectory.boolValue,
              let items = try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        for item in items {
            merge(item, into: destination.appending(path: item.lastPathComponent))
        }
    }

    static func importDefaults() {
        importLegacyDefaults()
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

    private static func importLegacyDefaults() {
        let defaults = UserDefaults.standard
        guard !isSandboxed, !defaults.bool(forKey: importedLegacyKey) else { return }
        for identifier in legacyIdentifiers where identifier != bundleIdentifier {
            let sources = [
                URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Preferences/\(identifier).plist"),
                container(for: identifier).appending(path: "Preferences/\(identifier).plist"),
            ]
            for source in sources {
                guard let values = NSDictionary(contentsOf: source) as? [String: Any] else { continue }
                for (key, value) in values where defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }
        }
        defaults.set(true, forKey: importedLegacyKey)
    }
}
