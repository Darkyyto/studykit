import Foundation

struct StudyDocument: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var fileName: String
    var addedAt = Date.now
    var openedAt = Date.now
    var pageCount: Int
    var lastPage = 0
    var goalID: Goal.ID?
    var flashcards: [SmartNotes.Item] = []

    var progress: Double {
        pageCount > 1 ? Double(lastPage) / Double(pageCount - 1) : 0
    }
}
