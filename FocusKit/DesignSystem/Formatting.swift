import Foundation

extension TimeInterval {
    var clock: String {
        let total = Int(rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    var compactDuration: String {
        let minutes = Int((self / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        let remainder = minutes % 60
        return remainder == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(remainder) min"
    }

    var hours: String {
        (self / 3600).formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension DateInterval {
    static var currentWeek: DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now) ?? DateInterval(start: .now, duration: 0)
    }
}
