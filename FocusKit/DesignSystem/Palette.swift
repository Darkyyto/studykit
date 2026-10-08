import AppKit
import SwiftUI

enum Palette {
    static let canvas = Color(light: 0xF6F4F1, dark: 0x161618)
    static let ink = Color(light: 0x1C1C22, dark: 0xF2F1F5)
    static let inkSecondary = Color(light: 0x6B6A72, dark: 0xA3A2AB)
    static let inkTertiary = Color(light: 0xA3A1A8, dark: 0x93929B)
    static let hairline = Color(light: 0x000000, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let surface = Color(light: 0xFFFFFF, dark: 0x242428)
    static let card = surface.opacity(0.72)
    static let record = Color(hex: 0xFF5A4E)
    static let rest = ModePalette(light: Color(light: 0xFFE4D2, dark: 0x3A2619), mid: Color(hex: 0xFFB48A), deep: Color(hex: 0xE9764A))
    static let neutral = ModePalette(light: Color(light: 0xEDE9F7, dark: 0x24222E), mid: Color(light: 0xD9E6F5, dark: 0x34405A), deep: Color(hex: 0x8E8AA8))
}

enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let key = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static var current: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct ModePalette: Equatable {
    let light: Color
    let mid: Color
    let deep: Color
}

extension FocusMode {
    var palette: ModePalette {
        switch self {
        case .flight: ModePalette(light: Color(light: 0xDCEEFF, dark: 0x15253A), mid: Color(hex: 0x8CC8FF), deep: Color(light: 0x2F86E8, dark: 0x4093F2))
        case .orbit: ModePalette(light: Color(light: 0xE9E4FF, dark: 0x221E3D), mid: Color(hex: 0xA99BFF), deep: Color(light: 0x6650E6, dark: 0x8C7BFF))
        case .bloom: ModePalette(light: Color(light: 0xDDF5E3, dark: 0x16291D), mid: Color(hex: 0x86D9A2), deep: Color(hex: 0x2FA35E))
        case .tide: ModePalette(light: Color(light: 0xD6F4F4, dark: 0x112B2C), mid: Color(hex: 0x6FD3D6), deep: Color(light: 0x14939B, dark: 0x1AA0A8))
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
    init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
