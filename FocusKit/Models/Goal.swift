import Foundation

struct Goal: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var notes = ""
    var tint: Tint = .amber
    var weeklyTargetMinutes = 300
    var createdAt = Date.now
    var isArchived = false
    var deadline: Date?

    var daysUntilDeadline: Int? {
        guard let deadline else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: deadline)).day
    }

    enum Tint: String, Codable, CaseIterable, Identifiable, Sendable {
        case amber, coral, rose, violet, sky, teal, moss, slate

        var id: String { rawValue }
    }
}
