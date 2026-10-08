import AppKit
import Observation
import QuickLookThumbnailing
import SwiftUI

@MainActor
@Observable
final class FileTray {
    struct Item: Identifiable, Hashable, Codable, Sendable {
        var id = UUID()
        let url: URL
        let original: URL

        var name: String { original.lastPathComponent }
    }

    static let enabledKey = "showsFileTray"
    private static let storageKey = "trayItems"
    private static let legacyKey = "trayFiles"

    private(set) var items: [Item] = []
    private(set) var thumbnails: [URL: NSImage] = [:]

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    nonisolated static var folder: URL {
        SandboxMigration.libraryRoot.appending(path: "Tray", directoryHint: .isDirectory)
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.storageKey), let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        } else if let paths = defaults.stringArray(forKey: Self.legacyKey) {
            items = paths.map { path in
                let url = URL(fileURLWithPath: path)
                return Item(url: url, original: url)
            }
            defaults.removeObject(forKey: Self.legacyKey)
            save()
        }
        prune()
    }

    var urls: [URL] {
        items.map(\.url)
    }

    func add(_ urls: [URL]) {
        let fresh = urls.filter { url in
            url.isFileURL && !items.contains { $0.original == url || $0.url == url }
        }
        guard !fresh.isEmpty else { return }
        Task {
            let stored = await Task.detached(priority: .userInitiated) { fresh.compactMap(Self.store) }.value
            guard !stored.isEmpty else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
                items.append(contentsOf: stored)
            }
            save()
        }
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        thumbnails[item.url] = nil
        Self.discard(item)
        save()
    }

    func clear() {
        items.forEach(Self.discard)
        items.removeAll()
        thumbnails.removeAll()
        save()
    }

    func prune() {
        let kept = items.filter { !Self.isStored($0) || FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false)) }
        guard kept.count != items.count else { return }
        items = kept
        save()
    }

    func open(_ item: Item) {
        if !NSWorkspace.shared.open(item.original) {
            NSWorkspace.shared.open(item.url)
        }
    }

    func reveal(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.original])
    }

    func copy(_ item: Item) {
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([item.url as NSURL])
    }

    func airDrop(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { return }
        NSApp.activate()
        service.perform(withItems: urls)
    }

    func loadThumbnail(for url: URL) async {
        guard thumbnails[url] == nil else { return }
        thumbnails[url] = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 112, height: 112), scale: 2, representationTypes: .thumbnail)
        let image: CGImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.cgImage)
            }
        }
        if let image, items.contains(where: { $0.url == url }) {
            thumbnails[url] = NSImage(cgImage: image, size: .zero)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private nonisolated static func store(_ source: URL) -> Item? {
        let manager = FileManager.default
        let id = UUID()
        let directory = folder.appending(path: id.uuidString, directoryHint: .isDirectory)
        let destination = directory.appending(path: source.lastPathComponent)
        do {
            guard isSameVolume(source, folder) else { throw CocoaError(.fileWriteVolumeReadOnly) }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: destination)
            return Item(id: id, url: destination, original: source)
        } catch {
            try? manager.removeItem(at: directory)
            return manager.fileExists(atPath: source.path(percentEncoded: false)) ? Item(id: id, url: source, original: source) : nil
        }
    }

    private nonisolated static func isSameVolume(_ source: URL, _ folder: URL) -> Bool {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let key = URLResourceKey.volumeIdentifierKey
        guard let a = try? source.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject,
              let b = try? folder.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject else { return false }
        return a.isEqual(b)
    }

    private nonisolated static func isStored(_ item: Item) -> Bool {
        item.url.path(percentEncoded: false).hasPrefix(folder.path(percentEncoded: false))
    }

    private nonisolated static func discard(_ item: Item) {
        guard isStored(item) else { return }
        try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
    }
}
