import SwiftUI

enum Motion {
    static let standard = Animation.spring(response: 0.38, dampingFraction: 1)
    static let quick = Animation.spring(response: 0.26, dampingFraction: 1)
    static let press = Animation.spring(response: 0.18, dampingFraction: 1)
    static let settle = Animation.spring(response: 0.5, dampingFraction: 0.82)
    static let morph = Animation.spring(response: 0.45, dampingFraction: 0.9)
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}
