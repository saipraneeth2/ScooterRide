import SwiftUI

@main
struct ScooterRideApp: App {
    @State private var library = RideLibrary.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RideHistoryView()
                .environment(library)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.reload() }
        }
    }
}
