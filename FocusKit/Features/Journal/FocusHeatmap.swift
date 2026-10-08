import SwiftUI

struct FocusHeatmap: View {
    let minutesByDay: [Date: Double]
    var tint = FocusMode.bloom.tone
    var calendar = Calendar.current

    private let gap: CGFloat = 5
    private let cell: CGFloat = 18

    var body: some View {
        let peak = max(60, minutesByDay.values.max() ?? 0)

        GeometryReader { proxy in
            let weeks = max(1, Int((proxy.size.width - 24) / (cell + gap)))
            let columns = days(weeks)
            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(row % 2 == 0 ? weekdaySymbol(row) : "")
                            .font(.rounded(9, weight: .semibold))
                            .foregroundStyle(Palette.inkTertiary)
                            .frame(width: 24, height: cell, alignment: .leading)
                    }
                }
                ForEach(columns.indices, id: \.self) { column in
                    VStack(spacing: gap) {
                        ForEach(columns[column], id: \.self) { day in
                            let minutes = minutesByDay[day] ?? 0
                            RoundedRectangle(cornerRadius: cell * 0.32)
                                .fill(minutes > 0 ? tint.opacity(0.3 + 0.7 * min(1, minutes / peak)) : tint.opacity(0.08))
                                .frame(width: cell, height: cell)
                                .opacity(day > .now ? 0 : 1)
                                .help("\(day.formatted(date: .abbreviated, time: .omitted)) · \(TimeInterval(minutes * 60).compactDuration)")
                        }
                    }
                }
            }
        }
        .frame(height: 7 * 18 + 6 * gap)
    }

    private func days(_ weeks: Int) -> [[Date]] {
        let today = calendar.startOfDay(for: .now)
        guard
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
            let first = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)
        else { return [] }

        return (0..<weeks).map { week in
            (0..<7).compactMap { offset in
                calendar.date(byAdding: .day, value: week * 7 + offset, to: first)
            }
        }
    }

    private func weekdaySymbol(_ row: Int) -> String {
        calendar.veryShortWeekdaySymbols[(calendar.firstWeekday - 1 + row) % 7]
    }
}
