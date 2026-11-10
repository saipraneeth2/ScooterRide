import SwiftUI
import RideKit

struct RootView: View {
    @Environment(RideViewModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            switch model.recorder.state {
            case .idle, .ended:
                StartView()
            case .active, .paused:
                ActiveRideView()
            }
        }
        .sheet(item: $model.lastFinishedRide) { ride in
            RideSummaryView(ride: ride, showsDone: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.appMovedToBackground() }
        }
    }
}
