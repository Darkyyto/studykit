import SwiftUI

enum Palette {
    static let canvas = Color(hex: 0xF6F4F1)
    static let ink = Color(hex: 0x1C1C22)
    static let inkSecondary = Color(hex: 0x6B6A72)
    static let inkTertiary = Color(hex: 0xA3A1A8)
    static let hairline = Color.black.opacity(0.06)
    static let card = Color.white.opacity(0.72)
    static let record = Color(hex: 0xFF5A4E)
    static let rest = ModePalette(light: Color(hex: 0xFFE4D2), mid: Color(hex: 0xFFB48A), deep: Color(hex: 0xE9764A))
    static let neutral = ModePalette(light: Color(hex: 0xEDE9F7), mid: Color(hex: 0xD9E6F5), deep: Color(hex: 0x8E8AA8))
}

struct ModePalette: Equatable {
    let light: Color
    let mid: Color
    let deep: Color
}

extension FocusMode {
    var palette: ModePalette {
        switch self {
        case .flight: ModePalette(light: Color(hex: 0xDCEEFF), mid: Color(hex: 0x8CC8FF), deep: Color(hex: 0x2F86E8))
        case .orbit: ModePalette(light: Color(hex: 0xE9E4FF), mid: Color(hex: 0xA99BFF), deep: Color(hex: 0x6650E6))
        case .bloom: ModePalette(light: Color(hex: 0xDDF5E3), mid: Color(hex: 0x86D9A2), deep: Color(hex: 0x2FA35E))
        case .tide: ModePalette(light: Color(hex: 0xD6F4F4), mid: Color(hex: 0x6FD3D6), deep: Color(hex: 0x14939B))
        }
    }
}

extension Goal.Tint {
    var color: Color {
        switch self {
        case .amber: Color(hex: 0xF5A623)
        case .coral: Color(hex: 0xFF7A59)
        case .rose: Color(hex: 0xF0628E)
        case .violet: Color(hex: 0x8B74F0)
        case .sky: Color(hex: 0x3D9BF0)
        case .teal: Color(hex: 0x1FB3B0)
        case .moss: Color(hex: 0x5DB65A)
        case .slate: Color(hex: 0x7D8696)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
