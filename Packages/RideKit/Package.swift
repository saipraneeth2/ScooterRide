// swift-tools-version: 6.0
// RideKit: platform-independent ride logic shared by the watch and iPhone apps.
// No CoreLocation, HealthKit or UI here, so everything is unit-testable on macOS.
import PackageDescription

let package = Package(
    name: "RideKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "RideKit", targets: ["RideKit"])],
    targets: [
        .target(name: "RideKit"),
        .testTarget(name: "RideKitTests", dependencies: ["RideKit"]),
    ],
    swiftLanguageModes: [.v5]
)
