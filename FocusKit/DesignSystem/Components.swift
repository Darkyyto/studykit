import SwiftUI

struct GlassCard<Content: View>: View {
    var radius: CGFloat = 28
    var padding: CGFloat = 22
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius))
    }
}

struct SurfaceCard<Content: View>: View {
    var radius: CGFloat = 24
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface.opacity(0.78), in: .rect(cornerRadius: radius))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.05), radius: 16, y: 8)
    }
}

struct GlassSegmented<Value: Hashable & Sendable>: View {
    let options: [Value]
    @Binding var selection: Value
    var tint: Color = Palette.ink
    let label: (Value) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(Motion.quick) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.rounded(13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .white : Palette.inkSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(tint)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

struct Stat: View {
    let label: String
    let value: String
    var unit: String?
    var size: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.numeric(size))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.rounded(size * 0.5, weight: .medium))
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
            Text(label)
                .font(.rounded(12, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = Palette.inkSecondary

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 72, height: 72)
                .glassEffect(.regular, in: .circle)
            VStack(spacing: 6) {
                Text(title)
                    .font(.rounded(20, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(message)
                    .font(.rounded(14))
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 40
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tint == nil ? Palette.ink : .white)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.pressable)
        .glassEffect(.regular.tint(tint).interactive(), in: .circle)
    }
}
