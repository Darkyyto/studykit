import Foundation

struct Recording: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var fileName: String
    var transcript: String
    var localeIdentifier: String
    var goalID: Goal.ID?
    var notes: SmartNotes?
    var stage: Stage?
    var wasInterrupted: Bool?

    enum Stage: String, Codable, Sendable {
        case recording
        case refining
        case ready
    }

}

struct SmartNotes: Codable, Hashable, Sendable {
    var text: String
    var summary: String
    var sections: [Section]
    var createdAt: Date

    struct Section: Codable, Hashable, Sendable {
        enum Style: String, Codable, Sendable {
            case bullets
            case checklist
            case definitions
            case flashcards
        }

        var title: String
        var style: Style
        var items: [Item]
    }

    struct Item: Codable, Hashable, Sendable {
        var primary: String
        var secondary: String?
    }
}
