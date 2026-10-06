import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class VoiceRecorder {
    enum State: Equatable {
        case idle
        case preparing
        case downloadingModel
        case recording(since: Date)
        case finishing
    }

    static let levelHistory = 96

    private(set) var state: State = .idle
    private(set) var finalizedText = ""
    private(set) var volatileText = ""
    private(set) var levels = [Float](repeating: 0, count: levelHistory)
    private(set) var errorMessage: String?
    private(set) var transcriptionLocale: Locale?
    private(set) var ownedBySession = false
    private(set) var recordedThisSession = false

    @ObservationIgnored private let library: Library
    @ObservationIgnored private var capture: AudioCapture?
    @ObservationIgnored private var transcription: Transcription?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var fileName: String?
    @ObservationIgnored private var goalID: Goal.ID?
    @ObservationIgnored private var noun = "Note"
    @ObservationIgnored private var draftID: Recording.ID?
    @ObservationIgnored private var lastDraftSave = Date.distantPast

    init(library: Library) {
        self.library = library
    }

    var isActive: Bool {
        state != .idle
    }

    var isBusy: Bool {
        state == .preparing || state == .downloadingModel || state == .finishing
    }

    func start(locale: Locale, goalID: Goal.ID?, vocabulary: [String] = [], noun: String = "Note") async {
        guard state == .idle else { return }
        reset()
        state = .preparing

        guard await AVAudioApplication.requestRecordPermission() else {
            fail("Microphone access is turned off. Enable it in System Settings › Privacy & Security › Microphone.")
            return
        }

        do {
            transcription = try await Transcription.prepare(for: locale, vocabulary: vocabulary) { [weak self] in
                self?.state = .downloadingModel
            }
        } catch {
            transcription = nil
            errorMessage = error.localizedDescription
        }

        let name = "\(UUID().uuidString).\(AudioCapture.fileExtension)"
        let capture = AudioCapture()
        do {
            try capture.start(
                writingTo: library.recordingsDirectory.appending(path: name),
                speechFormat: transcription?.format,
                speechInput: transcription?.input
            ) { [weak self] level in
                Task { @MainActor in self?.push(level) }
            }
        } catch {
            await transcription?.finish()
            transcription = nil
            fail(error.localizedDescription)
            return
        }

        self.capture = capture
        self.goalID = goalID
        self.noun = noun
        fileName = name
        transcriptionLocale = transcription?.locale
        state = .recording(since: .now)
        draftID = UUID()
        saveDraft(force: true)
        observeResults()
    }

    func stop() async -> Recording? {
        while state == .preparing || state == .downloadingModel {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard case .recording(let since) = state, let fileName else { return nil }
        state = .finishing
        capture?.stop()
        capture = nil
        await transcription?.finish()
        await resultsTask?.value
        transcription = nil
        resultsTask = nil

        appendFinal(volatileText)
        volatileText = ""

        var recording = makeRecording(fileName: fileName, since: since)
        recording.stage = .refining
        library.save(recording)
        library.flush()
        self.fileName = nil
        draftID = nil
        state = .idle
        return recording
    }

    private func makeRecording(fileName: String, since: Date) -> Recording {
        var recording = Recording(
            title: noun + ", " + since.formatted(.dateTime.weekday(.wide).hour().minute()),
            createdAt: since,
            duration: Date.now.timeIntervalSince(since),
            fileName: fileName,
            transcript: finalizedText.trimmingCharacters(in: .whitespacesAndNewlines),
            localeIdentifier: transcriptionLocale?.identifier ?? Locale.current.identifier,
            goalID: goalID
        )
        if let draftID {
            recording.id = draftID
        }
        if let existing = library.recordings.first(where: { $0.id == recording.id }) {
            recording.title = existing.title
        }
        return recording
    }

    private func saveDraft(force: Bool = false) {
        guard case .recording(let since) = state, let fileName, draftID != nil else { return }
        guard force || Date.now.timeIntervalSince(lastDraftSave) > 5 else { return }
        lastDraftSave = .now
        var draft = makeRecording(fileName: fileName, since: since)
        draft.stage = .recording
        library.save(draft)
    }

    func startForSession(locale: Locale, goalID: Goal.ID?, vocabulary: [String], noun: String) async {
        guard state == .idle, !ownedBySession else { return }
        ownedBySession = true
        recordedThisSession = false
        await start(locale: locale, goalID: goalID, vocabulary: vocabulary, noun: noun)
        if isActive {
            recordedThisSession = true
        } else {
            ownedBySession = false
        }
    }

    func finishSession(engine: FocusEngine, enhancer: NoteEnhancer, persona: Persona) {
        guard ownedBySession else { return }
        ownedBySession = false
        Task {
            guard let recording = await stop() else { return }
            engine.attachRecording(recording.id)
            enhancer.enhance(recording, for: persona)
        }
    }

    func stopNow(engine: FocusEngine, enhancer: NoteEnhancer, persona: Persona) {
        guard isActive else { return }
        ownedBySession = false
        Task {
            guard let recording = await stop() else { return }
            engine.attachRecording(recording.id)
            enhancer.enhance(recording, for: persona)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func observeResults() {
        guard let transcriber = transcription?.transcriber else { return }
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self?.appendFinal(text)
                        self?.volatileText = ""
                    } else {
                        self?.volatileText = text
                    }
                }
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    private func appendFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        finalizedText = Transcription.joined([finalizedText, trimmed])
        saveDraft()
    }

    private func push(_ level: Float) {
        guard case .recording = state else { return }
        levels.removeFirst()
        levels.append(level)
    }

    private func reset() {
        finalizedText = ""
        volatileText = ""
        errorMessage = nil
        levels = [Float](repeating: 0, count: Self.levelHistory)
    }

    private func fail(_ message: String) {
        errorMessage = message
        state = .idle
    }
}
