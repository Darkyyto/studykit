import Foundation

enum Persona: String, CaseIterable, Identifiable, Codable, Sendable {
    case student
    case professional
    case personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .student: "Student"
        case .professional: "Professional"
        case .personal: "Just for me"
        }
    }

    var pitch: String {
        switch self {
        case .student: "Study sessions, exam countdowns, lecture notes that turn into flashcards."
        case .professional: "Deep work blocks, project deadlines, meeting minutes with action items."
        case .personal: "Habits, reading and side projects, with calm soundscapes."
        }
    }

    var symbol: String {
        switch self {
        case .student: "graduationcap.fill"
        case .professional: "briefcase.fill"
        case .personal: "sparkles"
        }
    }

    var goalsTitle: String {
        switch self {
        case .student: "Subjects"
        case .professional: "Projects"
        case .personal: "Goals"
        }
    }

    var goalNoun: String {
        switch self {
        case .student: "subject"
        case .professional: "project"
        case .personal: "goal"
        }
    }

    var goalsSubtitle: String {
        switch self {
        case .student: "Everything you are studying, with exam dates."
        case .professional: "What you are shipping, and by when."
        case .personal: "The reasons behind every session."
        }
    }

    var recordingsTitle: String {
        switch self {
        case .student: "Lectures"
        case .professional: "Meetings"
        case .personal: "Recordings"
        }
    }

    var recordingsSubtitle: String {
        switch self {
        case .student: "Every lecture you recorded, transcribed and turned into notes."
        case .professional: "Every meeting you recorded, with minutes and action items."
        case .personal: "Everything you recorded, transcribed on this Mac."
        }
    }

    var recordingsEmptyTitle: String {
        switch self {
        case .student: "No lectures yet"
        case .professional: "No meetings yet"
        case .personal: "No recordings yet"
        }
    }

    var recordingsEmptyMessage: String {
        switch self {
        case .student: "Start a Lecture session from Focus. FocusKit records the professor, transcribes everything and writes notes and flashcards when it ends."
        case .professional: "Start a Meeting session from Focus. FocusKit transcribes the conversation and writes minutes when it ends."
        case .personal: "Start a Lecture or Meeting session from Focus and the recording will appear here."
        }
    }

    var deadlineLabel: String {
        switch self {
        case .student: "Exam"
        case .professional: "Deadline"
        case .personal: "Target date"
        }
    }

    var highlight: String {
        switch self {
        case .student: "Flashcards"
        case .professional: "Minutes"
        case .personal: "Soundscapes"
        }
    }

    var promise: String {
        switch self {
        case .student: "Lectures turn into notes and flashcards for your breaks."
        case .professional: "Meetings turn into minutes with action items."
        case .personal: "Every session lands in your journal."
        }
    }

    var focusQuestion: String {
        switch self {
        case .student: "What are you studying?"
        case .professional: "What will you get done?"
        case .personal: "What are you focusing on?"
        }
    }

    var focusPlaceholder: String {
        switch self {
        case .student: "Chapter 4 of organic chemistry, past exam papers…"
        case .professional: "Draft the Q4 proposal, review pull requests…"
        case .personal: "Read 30 pages, plan the trip, practice guitar…"
        }
    }

    var suggestions: [String] {
        switch self {
        case .student: ["Mathematics", "Physics", "Chemistry", "History", "Literature", "Economics", "Computer Science", "Biology", "Law", "Languages"]
        case .professional: ["Product launch", "Client work", "Writing", "Code reviews", "Planning", "Research", "Admin", "Learning"]
        case .personal: ["Reading", "Fitness", "Side project", "Music", "Writing", "Learning a language", "Meditation"]
        }
    }

    var rhythms: [Rhythm] {
        switch self {
        case .student:
            [
                Rhythm(name: "Pomodoro", detail: "4 × 25 min, 5 min breaks", minutes: 25, rounds: 4, breakMinutes: 5),
                Rhythm(name: "Study block", detail: "2 × 50 min, 10 min break", minutes: 50, rounds: 2, breakMinutes: 10),
                Rhythm(name: "Exam sprint", detail: "One 90 min session", minutes: 90, rounds: 1, breakMinutes: 0),
            ]
        case .professional:
            [
                Rhythm(name: "Deep work", detail: "2 × 50 min, 10 min break", minutes: 50, rounds: 2, breakMinutes: 10),
                Rhythm(name: "Maker block", detail: "One 90 min session", minutes: 90, rounds: 1, breakMinutes: 0),
                Rhythm(name: "Sprints", detail: "4 × 25 min, 5 min breaks", minutes: 25, rounds: 4, breakMinutes: 5),
            ]
        case .personal:
            [
                Rhythm(name: "Easy start", detail: "One 25 min session", minutes: 25, rounds: 1, breakMinutes: 0),
                Rhythm(name: "Pomodoro", detail: "4 × 25 min, 5 min breaks", minutes: 25, rounds: 4, breakMinutes: 5),
                Rhythm(name: "Long focus", detail: "One 60 min session", minutes: 60, rounds: 1, breakMinutes: 0),
            ]
        }
    }

    var suggestedMode: FocusMode {
        switch self {
        case .student: .bloom
        case .professional: .flight
        case .personal: .tide
        }
    }

    struct Rhythm: Hashable, Sendable {
        let name: String
        let detail: String
        let minutes: Int
        let rounds: Int
        let breakMinutes: Int
    }
}
