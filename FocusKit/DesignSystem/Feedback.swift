import SwiftUI

struct Waveform: View {
    let levels: [Float]

    var body: some View {
        Canvas { context, size in
            let count = levels.count
            guard count > 0 else { return }
            let spacing: CGFloat = 4
            let barWidth = max(2, (size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            for (index, level) in levels.enumerated() {
                let height = max(barWidth, CGFloat(level) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + spacing),
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let recency = Double(index) / Double(count)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(Palette.record.opacity(0.15 + 0.85 * recency))
                )
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Palette.record)
            Text(message)
                .font(.rounded(13, weight: .medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: 460)
        .background(Palette.surface, in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        .padding(24)
    }
}
