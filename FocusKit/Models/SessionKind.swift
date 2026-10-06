import Foundation

enum Companion: String, Codable, CaseIterable, Identifiable, Sendable {
    case notes
    case transcript
    case tasks
    case parkingLot
    case recall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: "Notes"
        case .transcript: "Live"
        case .tasks: "Tasks"
        case .parkingLot: "Parked"
        case .recall: "Recall"
        }
    }

    var symbol: String {
        switch self {
        case .notes: "square.and.pencil"
        case .transcript: "waveform"
        case .tasks: "checklist"
        case .parkingLot: "tray.and.arrow.down"
        case .recall: "rectangle.on.rectangle.angled"
        }
    }
}

enum SessionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case study
    case lecture
    case examPrep
    case reading
    case deepWork
    case coding
    case writing
    case meeting
    case admin
    case focus
    case creative
    case learning

    var id: String { rawValue }

    static func options(for persona: Persona) -> [SessionKind] {
        switch persona {
        case .student: [.study, .lecture, .examPrep, .reading]
        case .professional: [.deepWork, .coding, .writing, .meeting, .admin]
        case .personal: [.focus, .creative, .learning, .reading]
        }
    }

    var title: String {
        switch self {
        case .study: "Study"
        case .lecture: "Lecture"
        case .examPrep: "Exam prep"
        case .reading: "Reading"
        case .deepWork: "Deep work"
        case .coding: "Coding"
        case .writing: "Writing"
        case .meeting: "Meeting"
        case .admin: "Admin"
        case .focus: "Focus"
        case .creative: "Creative"
        case .learning: "Learning"
        }
    }

    var symbol: String {
        switch self {
        case .study: "book.fill"
        case .lecture: "person.wave.2.fill"
        case .examPrep: "checkmark.seal.fill"
        case .reading: "text.book.closed.fill"
        case .deepWork: "brain.head.profile.fill"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .writing: "pencil.and.scribble"
        case .meeting: "person.2.fill"
        case .admin: "tray.full.fill"
        case .focus: "scope"
        case .creative: "paintpalette.fill"
        case .learning: "lightbulb.fill"
        }
    }

    var pitch: String {
        switch self {
        case .study: "Notes on the side, flashcards from your lectures in every break."
        case .lecture: "Records the lecture and transcribes it next to your notes."
        case .examPrep: "Check off topics, then quiz yourself between rounds."
        case .reading: "A quiet session with a margin for your thoughts."
        case .deepWork: "One task list, one parking lot for distractions."
        case .coding: "Tasks for the branch, a parking lot for every rabbit hole."
        case .writing: "A clean page with a live word count."
        case .meeting: "Live transcript beside your notes, minutes when it ends."
        case .admin: "Clear the small stuff fast, one checkbox at a time."
        case .focus: "Pick one thing and give it your full attention."
        case .creative: "A sketchpad for ideas while you make."
        case .learning: "Take notes, then test yourself in the breaks."
        }
    }

    var companions: [Companion] {
        switch self {
        case .study: [.notes, .recall, .parkingLot]
        case .lecture: [.transcript, .notes]
        case .examPrep: [.tasks, .recall, .parkingLot]
        case .reading: [.notes]
        case .deepWork: [.tasks, .parkingLot]
        case .coding: [.tasks, .parkingLot, .notes]
        case .writing: [.notes, .parkingLot]
        case .meeting: [.transcript, .notes, .tasks]
        case .admin: [.tasks]
        case .focus: [.tasks, .parkingLot]
        case .creative: [.notes, .parkingLot]
        case .learning: [.notes, .recall]
        }
    }

    var usesRecallBreaks: Bool {
        companions.contains(.recall)
    }

    var recordsAudio: Bool {
        companions.contains(.transcript)
    }

    var plansTasks: Bool {
        companions.contains(.tasks)
    }

    var defaults: (minutes: Int, rounds: Int, breakMinutes: Int) {
        switch self {
        case .study, .learning: (25, 4, 5)
        case .lecture: (90, 1, 0)
        case .examPrep: (45, 3, 10)
        case .reading: (40, 1, 0)
        case .deepWork, .coding: (50, 2, 10)
        case .writing, .creative: (45, 2, 10)
        case .meeting: (30, 1, 0)
        case .admin: (25, 1, 0)
        case .focus: (25, 1, 0)
        }
    }

    var notesPlaceholder: String {
        switch self {
        case .lecture: "Your own notes. The transcript is in the Live tab."
        case .meeting: "Agenda, your points, anything you want in the minutes."
        case .writing: "Start writing."
        case .coding: "Scratchpad: commands, links, ideas for the PR."
        case .creative: "Sketch ideas, references, the next step."
        default: "Key ideas, questions, anything worth remembering."
        }
    }
}

struct SessionTask: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var isDone = false
}
