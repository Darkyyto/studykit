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
        let links = urls.filter { ["http", "https"].contains($0.scheme?.lowercased()) }
        guard !fresh.isEmpty || !links.isEmpty else { return }
        Task {
            var stored = await Task.detached(priority: .userInitiated) { fresh.compactMap(Self.store) }.value
            for link in links {
                if Self.looksLikeImage(link), let data = await Self.download(link) {
                    if let item = Self.write(data, named: link.lastPathComponent) { stored.append(item) }
                } else if let item = Self.writeLink(link) {
                    stored.append(item)
                }
            }
            append(stored)
        }
    }

    /// Whatever is on the clipboard: copied files, an image (from a browser or a screenshot), a link, or text.
    @discardableResult
    func pasteFromClipboard() -> Bool {
        let board = NSPasteboard.general
        guard Set((board.types ?? []).map(\.rawValue)).isDisjoint(with: ClipboardHistory.privateTypes) else { return false }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            add(urls)
            return true
        }
        if let data = board.data(forType: .png) ?? board.data(forType: .tiff) {
            Task {
                let item = await Task.detached(priority: .userInitiated) { () -> Item? in
                    let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) ?? data
                    return Self.write(png, named: "Image \(Self.stamp()).png")
                }.value
                if let item { append([item]) }
            }
            return true
        }
        if let url = (board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first(where: { ["http", "https"].contains($0.scheme?.lowercased()) }) {
            add([url])
            return true
        }
        guard let string = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return false }
        if !string.contains(where: \.isWhitespace), let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil {
            add([url])
            return true
        }
        let title = String(string.prefix(32)).components(separatedBy: .newlines).first ?? "Text"
        if let item = Self.write(Data(string.utf8), named: "\(Self.clean(title)).txt") {
            append([item])
            return true
        }
        return false
    }

    var clipboardHasContent: Bool {
        NSPasteboard.general.types?.isEmpty == false
    }

    private func append(_ stored: [Item]) {
        guard !stored.isEmpty else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
            items.append(contentsOf: stored)
        }
        save()
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

    private nonisolated static func write(_ data: Data, named name: String) -> Item? {
        let fallback = name.isEmpty ? "Item" : name
        let id = UUID()
        let directory = folder.appending(path: id.uuidString, directoryHint: .isDirectory)
        let destination = directory.appending(path: clean(fallback))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: destination)
            return Item(id: id, url: destination, original: destination)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }

    private nonisolated static func writeLink(_ url: URL) -> Item? {
        let plist: [String: Any] = ["URL": url.absoluteString]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return nil }
        let name = (url.host() ?? "Link").replacingOccurrences(of: "www.", with: "")
        let detail = url.lastPathComponent == "/" || url.lastPathComponent.isEmpty ? "" : " – " + url.lastPathComponent
        return write(data, named: "\(name)\(detail).webloc")
    }

    private nonisolated static func looksLikeImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"].contains(url.pathExtension.lowercased())
    }

    private nonisolated static func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 50_000_000 else { return nil }
        return data
    }

    private nonisolated static func clean(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "[/:\\n\\r]", with: "-", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Item" : String(cleaned.prefix(80))
    }

    private nonisolated static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH.mm.ss"
        return formatter.string(from: .now)
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
