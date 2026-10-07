import AVFoundation
import Foundation
import FoundationModels
import NaturalLanguage
import Observation

@MainActor
@Observable
final class NoteEnhancer {
    enum Availability: Equatable {
        case available
        case unavailable(String)
    }

    enum Phase: Equatable {
        case transcribing
        case writing
    }

    private(set) var phases: [Recording.ID: Phase] = [:]
    private(set) var failures: [Recording.ID: String] = [:]

    @ObservationIgnored private let library: Library
    private static let chunkLength = 1_800
    private static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private static let digestLength = 5_000

    init(library: Library) {
        self.library = library
    }

    var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            .available
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable("Turn on Apple Intelligence in System Settings to polish notes.")
        case .unavailable(.modelNotReady):
            .unavailable("Apple Intelligence is still getting ready. Try again in a few minutes.")
        case .unavailable:
            .unavailable("This Mac does not support Apple Intelligence.")
        }
    }

    func isWorking(on recording: Recording) -> Bool {
        phases[recording.id] != nil
    }

    func phase(of recording: Recording) -> Phase? {
        phases[recording.id]
    }

    func resumePending(for persona: Persona) {
        for var recording in library.recordings where recording.stage == .recording || recording.stage == .refining {
            if recording.stage == .recording {
                recording.wasInterrupted = true
                recording.stage = .refining
                if let file = try? AVAudioFile(forReading: library.audioURL(for: recording)) {
                    recording.duration = Double(file.length) / file.fileFormat.sampleRate
                }
                library.save(recording)
            }
            enhance(recording, for: persona)
        }
    }

    func enhance(_ recording: Recording, for persona: Persona) {
        guard phases[recording.id] == nil else { return }
        failures[recording.id] = nil
        let language = Locale(identifier: recording.localeIdentifier).localizedString(forLanguageCode: recording.localeIdentifier)
            ?? recording.localeIdentifier

        Task {
            defer { phases[recording.id] = nil }
            var marked: String?
            if recording.stage == .refining {
                phases[recording.id] = .transcribing
                let refined = try? await Transcription.transcribe(
                    file: library.audioURL(for: recording),
                    locale: Locale(identifier: recording.localeIdentifier),
                    vocabulary: library.activeGoals.map(\.title)
                )
                guard var current = library.recordings.first(where: { $0.id == recording.id }) else { return }
                if let refined, refined.plain.count >= current.transcript.count * 2 / 3 {
                    current.transcript = refined.plain
                    marked = refined.marked
                }
                current.stage = .ready
                library.save(current)
            }

            guard let current = library.recordings.first(where: { $0.id == recording.id }) else { return }
            let transcript = (marked ?? current.transcript).trimmingCharacters(in: .whitespacesAndNewlines)
            guard availability == .available, !transcript.isEmpty else { return }
            phases[recording.id] = .writing
            do {
                let polished = try await Self.polish(transcript, language: language)
                let excerpt = String(polished.prefix(Self.digestLength))
                let digest = try? await Self.digest(excerpt, language: language, persona: persona)
                guard var current = library.recordings.first(where: { $0.id == recording.id }) else { return }
                if let digest, current.isNamed != true, current.title == recording.title, !digest.title.isEmpty {
                    current.title = digest.title
                }
                current.notes = SmartNotes(
                    text: polished,
                    summary: digest?.summary ?? "",
                    sections: digest?.sections.filter { !$0.items.isEmpty } ?? [],
                    createdAt: .now
                )
                library.save(current)
            } catch {
                failures[recording.id] = Self.describe(error)
            }
        }
    }

    func flashcards(from text: String) async throws -> [SmartNotes.Item] {
        let excerpt = String(text.prefix(Self.digestLength))
        let language = NLLanguageRecognizer.dominantLanguage(for: excerpt).flatMap { Locale.current.localizedString(forLanguageCode: $0.rawValue) } ?? "the language of the text"
        let session = LanguageModelSession(model: Self.model, instructions: """
            You write study flashcards from textbook pages. Write everything in \(language).
            Only use information that appears in the text. Questions must be answerable from it.
            """)
        let deck = try await session.respond(to: "Pages:\n\(excerpt)", generating: FlashcardDeck.self, options: GenerationOptions(temperature: 0.3)).content
        return deck.cards.map { SmartNotes.Item(primary: $0.question, secondary: $0.answer) }
    }

    func dismissFailure(for recording: Recording) {
        failures[recording.id] = nil
    }

    func describeFailure(_ error: Error) -> String {
        Self.describe(error)
    }

    private static func polish(_ transcript: String, language: String) async throws -> String {
        var polished: [String] = []
        var refused = 0
        var lastError: Error?
        let pieces = chunks(of: transcript)
        for chunk in pieces {
            let session = LanguageModelSession(model: model, instructions: """
                You edit raw speech-to-text transcripts of lectures, meetings and voice notes, often recorded from far away or in a noisy room.
                Rewrite the text you receive so it reads naturally, in \(language).
                Fix grammar, punctuation and capitalization. Remove filler words, stutters, repetitions and false starts.
                Words wrapped in ⟦ ⟧ were hard to hear. Keep them when they fit, otherwise replace them with the word that makes sense in context. Never leave the ⟦ ⟧ marks in your reply.
                When a word or a phrase makes no sense, it was misheard: replace it with the most plausible words for the topic, such as the right technical term or name.
                When a sentence is garbled beyond repair, drop it rather than guess its content.
                Split the result into short paragraphs.
                Never add facts, opinions or content that is not in the original. Never translate.
                Reply with the rewritten text only.
                """)
            do {
                let response = try await session.respond(to: chunk, options: GenerationOptions(temperature: 0.2))
                polished.append(response.content.replacing("⟦", with: "").replacing("⟧", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                refused += 1
                lastError = error
                polished.append(chunk.replacing("⟦", with: "").replacing("⟧", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        if refused == pieces.count, let lastError {
            throw lastError
        }
        return polished.joined(separator: "\n\n")
    }

    private static func digest(_ text: String, language: String, persona: Persona) async throws -> (title: String, summary: String, sections: [SmartNotes.Section]) {
        let clean = { (values: [String]) in values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        switch persona {
        case .student:
            let session = LanguageModelSession(model: model, instructions: """
                You turn transcripts of lectures and study sessions into study material. Write everything in \(language).
                Only use information that appears in the transcript. Be precise and concise, like a good student would.
                """)
            let notes = try await session.respond(to: "Lecture:\n\(text)", generating: StudyDigest.self, options: GenerationOptions(temperature: 0.3)).content
            return (notes.title, notes.summary, [
                SmartNotes.Section(title: "Key concepts", style: .definitions, items: notes.concepts.map { SmartNotes.Item(primary: $0.term, secondary: $0.definition) }),
                SmartNotes.Section(title: "Flashcards", style: .flashcards, items: notes.flashcards.map { SmartNotes.Item(primary: $0.question, secondary: $0.answer) }),
            ])
        case .professional:
            let session = LanguageModelSession(model: model, instructions: """
                You write crisp meeting minutes from transcripts. Write everything in \(language).
                Only use information that appears in the transcript. When nobody owns a task, leave the owner empty.
                """)
            let notes = try await session.respond(to: "Meeting:\n\(text)", generating: MeetingDigest.self, options: GenerationOptions(temperature: 0.3)).content
            return (notes.title, notes.summary, [
                SmartNotes.Section(title: "Decisions", style: .bullets, items: clean(notes.decisions).map { SmartNotes.Item(primary: $0) }),
                SmartNotes.Section(title: "Action items", style: .checklist, items: notes.actions.map { SmartNotes.Item(primary: $0.task, secondary: $0.owner.isEmpty ? nil : $0.owner) }),
            ])
        case .personal:
            let session = LanguageModelSession(model: model, instructions: """
                You organize personal voice notes. Write everything in \(language).
                Only use information that appears in the note.
                """)
            let notes = try await session.respond(to: "Note:\n\(text)", generating: NoteDigest.self, options: GenerationOptions(temperature: 0.3)).content
            return (notes.title, notes.summary, [
                SmartNotes.Section(title: "Key points", style: .bullets, items: clean(notes.keyPoints).map { SmartNotes.Item(primary: $0) }),
                SmartNotes.Section(title: "To do", style: .checklist, items: clean(notes.actions).map { SmartNotes.Item(primary: $0) }),
            ])
        }
    }

    private static func chunks(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let sentences = text.split(whereSeparator: { ".!?\n".contains($0) }).map { String($0) }
        var cursor = text.startIndex
        for sentence in sentences {
            guard let range = text.range(of: sentence, range: cursor..<text.endIndex) else { continue }
            let end = text.index(range.upperBound, offsetBy: 1, limitedBy: text.endIndex) ?? text.endIndex
            let piece = String(text[cursor..<end])
            cursor = end
            if current.count + piece.count > chunkLength, !current.isEmpty {
                result.append(current)
                current = ""
            }
            current += piece
        }
        if cursor < text.endIndex {
            current += text[cursor...]
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(current)
        }
        return result
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .unsupportedLanguageOrLocale:
                return "Apple Intelligence does not support this language yet."
            case .guardrailViolation:
                return "Apple Intelligence declined to rewrite this note. The original transcript is still here."
            case .exceededContextWindowSize:
                return "This note is too long to polish in one go."
            default:
                break
            }
        }
        return "Could not polish this note. \(error.localizedDescription)"
    }
}

@Generable
struct FlashcardDeck {
    @Guide(description: "Exam style questions with short, correct answers.", .count(3...8))
    var cards: [StudyDigest.Flashcard]
}

@Generable
struct StudyDigest {
    @Guide(description: "A short, specific title for the lecture. At most six words. No quotes.")
    var title: String

    @Guide(description: "Two or three sentences that capture what the lecture covered.")
    var summary: String

    @Guide(description: "The most important concepts with a one sentence definition each.", .maximumCount(6))
    var concepts: [Concept]

    @Guide(description: "Questions a teacher could ask in an exam about this lecture, with short correct answers.", .maximumCount(6))
    var flashcards: [Flashcard]

    @Generable
    struct Concept {
        var term: String
        var definition: String
    }

    @Generable
    struct Flashcard {
        var question: String
        var answer: String
    }
}

@Generable
struct MeetingDigest {
    @Guide(description: "A short, specific title for the meeting. At most six words. No quotes.")
    var title: String

    @Guide(description: "Two sentences that capture what the meeting was about and its outcome.")
    var summary: String

    @Guide(description: "Decisions that were made. Empty when there are none.", .maximumCount(6))
    var decisions: [String]

    @Guide(description: "Concrete follow-up tasks.", .maximumCount(8))
    var actions: [ActionItem]

    @Generable
    struct ActionItem {
        var task: String
        @Guide(description: "The person responsible, or an empty string when unknown.")
        var owner: String
    }
}

@Generable
struct NoteDigest {
    @Guide(description: "A short, specific title for the note. At most six words. No quotes.")
    var title: String

    @Guide(description: "One or two sentences that capture what the note is about.")
    var summary: String

    @Guide(description: "The most important ideas in the note, each a short sentence.", .maximumCount(5))
    var keyPoints: [String]

    @Guide(description: "Concrete tasks or next steps the speaker mentioned. Empty when there are none.", .maximumCount(5))
    var actions: [String]
}
