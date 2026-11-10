import SwiftUI
import UIKit

@main
struct ScooterRideApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

/// Starts WatchConnectivity on every launch, including background launches when Apple Watch
/// checks in while the iPhone is locked, so waiting rides are delivered and answered.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = RideLibrary.shared   // its init activates the WatchConnectivity session
        RidingAlerts.shared.resumeIfEnabled()   // receives the location event iOS relaunched us for
        return true
    }
}
