import SwiftUI

@main
struct ScooterRideWatchApp: App {
    @State private var model = RideViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
