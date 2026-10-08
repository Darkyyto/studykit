import SwiftUI

extension Font {
    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func numeric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

extension View {
    func displayTracking(_ size: CGFloat) -> some View {
        tracking(size >= 28 ? -size * 0.022 : 0)
    }
}

struct Eyebrow: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.rounded(12, weight: .semibold))
            .foregroundStyle(Palette.inkSecondary)
    }
}

struct ScreenTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.rounded(34, weight: .bold))
                .displayTracking(34)
                .foregroundStyle(Palette.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.rounded(15))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}
