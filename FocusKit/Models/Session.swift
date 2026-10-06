import Foundation

struct Session: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var mode: FocusMode
    var goalID: Goal.ID?
    var intention: String
    var startedAt: Date
    var endedAt: Date
    var plannedFocus: TimeInterval
    var focused: TimeInterval
    var roundsPlanned: Int
    var roundsCompleted: Int
    var outcome: Outcome
    var route: Route?
    var note = ""
    var kind: SessionKind?
    var notes: String?
    var tasks: [SessionTask]?
    var parked: [String]?
    var recordingID: Recording.ID?
    var documentID: StudyDocument.ID?
    var pages: ClosedRange<Int>?

    enum Outcome: String, Codable, Sendable {
        case completed
        case stopped
    }

    struct Route: Codable, Hashable, Sendable {
        var origin: Airport.Code
        var destination: Airport.Code
    }
}

struct FocusPlan: Equatable, Sendable {
    var mode: FocusMode
    var intention: String
    var goalID: Goal.ID?
    var focusDuration: TimeInterval
    var rounds: Int
    var breakDuration: TimeInterval
    var route: Session.Route?
    var seat: String?
    var variant: String?
    var kind: SessionKind = .focus
    var tasks: [SessionTask] = []
    var documentID: StudyDocument.ID?

    struct Segment: Equatable, Sendable {
        enum Kind: Sendable {
            case focus
            case rest
        }

        let kind: Kind
        let duration: TimeInterval
        let round: Int
    }

    var segments: [Segment] {
        (0..<rounds).flatMap { round -> [Segment] in
            let focus = Segment(kind: .focus, duration: focusDuration, round: round)
            guard round < rounds - 1, breakDuration > 0 else { return [focus] }
            return [focus, Segment(kind: .rest, duration: breakDuration, round: round)]
        }
    }

    var totalFocus: TimeInterval {
        focusDuration * Double(rounds)
    }

    var totalDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }
}
