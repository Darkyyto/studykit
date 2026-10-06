import SwiftUI

struct RitualHost: View {
    let plan: FocusPlan
    let cancel: () -> Void
    let begin: (FocusPlan) -> Void

    var body: some View {
        switch plan.mode {
        case .flight:
            CheckInFlow(plan: plan, cancel: cancel) { seat in
                var plan = plan
                plan.seat = seat
                begin(plan)
            }
        case .orbit:
            MissionBriefing(plan: plan, cancel: cancel, begin: begin)
        case .bloom:
            SeedPicker(plan: plan, cancel: cancel, begin: begin)
        case .tide:
            HarborDeparture(plan: plan, cancel: cancel, begin: begin)
        }
    }
}
