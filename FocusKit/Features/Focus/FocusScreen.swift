import SwiftUI

struct FocusScreen: View {
    @Environment(FocusEngine.self) private var engine

    var body: some View {
        ZStack {
            if engine.isActive || engine.phase.isComplete {
                SessionView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.03)),
                        removal: .opacity
                    ))
            } else {
                FocusSetup()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .scale(scale: 0.97))
                    ))
            }
        }
        .animation(Motion.morph, value: engine.isActive || engine.phase.isComplete)
    }
}
