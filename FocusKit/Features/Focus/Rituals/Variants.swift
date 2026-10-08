import SwiftUI

enum OrbitBody: String, CaseIterable, Identifiable {
    case moon, mars, saturn, neptune

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var detail: String {
        switch self {
        case .moon: "A quiet loop, close to home"
        case .mars: "Red dust and long focus"
        case .saturn: "Rings for the deep dive"
        case .neptune: "The far, calm blue"
        }
    }

    var palette: ModePalette {
        switch self {
        case .moon: ModePalette(light: Color(light: 0xF1F1F4, dark: 0x1E1F24), mid: Color(hex: 0xC3C6CF), deep: Color(hex: 0x7C8190))
        case .mars: ModePalette(light: Color(light: 0xFFE2D3, dark: 0x3A2118), mid: Color(hex: 0xF0905F), deep: Color(hex: 0xB9452A))
        case .saturn: ModePalette(light: Color(light: 0xFBEFD5, dark: 0x352B17), mid: Color(hex: 0xE6C27F), deep: Color(hex: 0xA97F33))
        case .neptune: FocusMode.orbit.palette
        }
    }

    var hasRings: Bool {
        self == .saturn || self == .neptune
    }

    static func resolve(_ value: String?) -> OrbitBody {
        value.flatMap(OrbitBody.init(rawValue:)) ?? .neptune
    }
}

enum FlowerKind: String, CaseIterable, Identifiable {
    case daisy, sunflower, tulip, lavender

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var detail: String {
        switch self {
        case .daisy: "Cheerful and quick to bloom"
        case .sunflower: "Tall, bright, patient"
        case .tulip: "Elegant and focused"
        case .lavender: "Calm and fragrant"
        }
    }

    var petal: Color {
        switch self {
        case .daisy: Color(hex: 0xFF8FB1)
        case .sunflower: Color(hex: 0xFFC83D)
        case .tulip: Color(hex: 0xF0564A)
        case .lavender: Color(hex: 0x9B7BE8)
        }
    }

    var heart: Color {
        switch self {
        case .daisy: Color(hex: 0xFFC94D)
        case .sunflower: Color(hex: 0x7A4A21)
        case .tulip: Color(hex: 0xC93A33)
        case .lavender: Color(hex: 0x7A5BD0)
        }
    }

    static func resolve(_ value: String?) -> FlowerKind {
        value.flatMap(FlowerKind.init(rawValue:)) ?? .daisy
    }
}

enum BoatKind: String, CaseIterable, Identifiable {
    case sailboat, paper, catamaran

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sailboat: "Sailboat"
        case .paper: "Paper boat"
        case .catamaran: "Catamaran"
        }
    }
}

enum SkyKind: String, CaseIterable, Identifiable {
    case day, sunset

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var sun: (Color, Color) {
        switch self {
        case .day: (Color(hex: 0xFFE7B0), Color(hex: 0xFFC46B))
        case .sunset: (Color(hex: 0xFFB38A), Color(hex: 0xF0705A))
        }
    }

    var water: ModePalette {
        switch self {
        case .day: FocusMode.tide.palette
        case .sunset: ModePalette(light: Color(light: 0xFFE3D6, dark: 0x3A2622), mid: Color(hex: 0x8FB5D6), deep: Color(hex: 0x3F5F9A))
        }
    }
}

struct TideVariant {
    var boat: BoatKind
    var sky: SkyKind

    var rawValue: String {
        "\(boat.rawValue).\(sky.rawValue)"
    }

    static func resolve(_ value: String?) -> TideVariant {
        let parts = (value ?? "").split(separator: ".").map(String.init)
        return TideVariant(
            boat: parts.first.flatMap(BoatKind.init(rawValue:)) ?? .sailboat,
            sky: parts.dropFirst().first.flatMap(SkyKind.init(rawValue:)) ?? .day
        )
    }
}
