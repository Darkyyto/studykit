import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class Library {
    private(set) var goals: [Goal] = []
    private(set) var sessions: [Session] = []
    private(set) var recordings: [Recording] = []
    private(set) var documents: [StudyDocument] = []
    var pendingDocumentID: StudyDocument.ID?

    @ObservationIgnored private let location: Location
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.focuskit.FocusKit", category: "Library")

    init(location: Location = .standard) {
        self.location = location
        load()
    }

    var activeGoals: [Goal] {
        goals.filter { !$0.isArchived }
    }

    var recordingsDirectory: URL {
        location.recordings
    }

    func goal(_ id: Goal.ID?) -> Goal? {
        guard let id else { return nil }
        return goals.first { $0.id == id }
    }

    func save(_ goal: Goal) {
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
        } else {
            goals.append(goal)
        }
        scheduleSave()
    }

    func delete(_ goal: Goal) {
        goals.removeAll { $0.id == goal.id }
        for index in sessions.indices where sessions[index].goalID == goal.id {
            sessions[index].goalID = nil
        }
        for index in recordings.indices where recordings[index].goalID == goal.id {
            recordings[index].goalID = nil
        }
        scheduleSave()
    }

    func log(_ session: Session) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        scheduleSave()
    }

    func delete(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        scheduleSave()
    }

    func save(_ recording: Recording) {
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index] = recording
        } else {
            recordings.insert(recording, at: 0)
        }
        scheduleSave()
    }

    func delete(_ recording: Recording) {
        recordings.removeAll { $0.id == recording.id }
        try? FileManager.default.removeItem(at: audioURL(for: recording))
        scheduleSave()
    }

    func save(_ document: StudyDocument) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        } else {
            documents.insert(document, at: 0)
        }
        scheduleSave()
    }

    func delete(_ document: StudyDocument) {
        documents.removeAll { $0.id == document.id }
        try? FileManager.default.removeItem(at: url(for: document))
        scheduleSave()
    }

    func url(for document: StudyDocument) -> URL {
        location.documents.appending(path: document.fileName)
    }

    @discardableResult
    func importDocument(from source: URL, pageCount: Int) throws -> StudyDocument {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let title = source.deletingPathExtension().lastPathComponent
        if let existing = documents.first(where: { $0.title == title && $0.pageCount == pageCount }) {
            var touched = existing
            touched.openedAt = .now
            save(touched)
            return touched
        }
        try FileManager.default.createDirectory(at: location.documents, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).pdf"
        try FileManager.default.copyItem(at: source, to: location.documents.appending(path: fileName))
        let document = StudyDocument(title: title, fileName: fileName, pageCount: pageCount)
        save(document)
        return document
    }

    func audioURL(for recording: Recording) -> URL {
        location.recordings.appending(path: recording.fileName)
    }

    func focusedTime(for goalID: Goal.ID? = nil, in interval: DateInterval? = nil) -> TimeInterval {
        sessions
            .filter { goalID == nil || $0.goalID == goalID }
            .filter { interval?.contains($0.startedAt) ?? true }
            .reduce(0) { $0 + $1.focused }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: location.database)
            let snapshot = try JSONDecoder.library.decode(Snapshot.self, from: data)
            goals = snapshot.goals
            sessions = snapshot.sessions
            recordings = snapshot.recordings
            documents = snapshot.documents ?? []
        } catch CocoaError.fileReadNoSuchFile {
            return
        } catch {
            logger.error("Failed to load library: \(error.localizedDescription)")
        }
    }

    func flush() {
        guard let pending = pendingSave else { return }
        pending.cancel()
        pendingSave = nil
        Self.write(snapshot, to: location.database, logger: logger)
    }

    private var snapshot: Snapshot {
        Snapshot(goals: goals, sessions: sessions, recordings: recordings, documents: documents)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = snapshot
        let url = location.database
        let logger = logger
        pendingSave = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: url, logger: logger)
        }
    }

    private nonisolated static func write(_ snapshot: Snapshot, to url: URL, logger: Logger) {
        do {
            let data = try JSONEncoder.library.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save library: \(error.localizedDescription)")
        }
    }
}

extension Library {
    struct Location: Sendable {
        let root: URL

        var database: URL { root.appending(path: "Library.json") }
        var recordings: URL { root.appending(path: "Recordings", directoryHint: .isDirectory) }
        var documents: URL { root.appending(path: "Documents", directoryHint: .isDirectory) }

        static var standard: Location {
            let root = SandboxMigration.libraryRoot
            let location = Location(root: root)
            try? FileManager.default.createDirectory(at: location.recordings, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: location.documents, withIntermediateDirectories: true)
            return location
        }
    }

    private struct Snapshot: Codable, Sendable {
        var goals: [Goal]
        var sessions: [Session]
        var recordings: [Recording]
        var documents: [StudyDocument]?
    }
}

private extension JSONEncoder {
    static var library: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var library: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
