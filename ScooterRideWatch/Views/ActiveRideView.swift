import SwiftUI
import RideKit

/// The in-ride screen. Designed for a quick glance while stopped: one huge number,
/// four secondary values, and two large controls. Ending a ride needs confirmation.
struct ActiveRideView: View {
    @Environment(RideViewModel.self) private var model
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var confirmEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let m = model.metrics(at: context.date)
            ScrollView {
                VStack(spacing: 6) {
                    speedBlock(m)
                    statsGrid(m)
                    if !isLuminanceReduced { controls(m) }
                    if let message = model.errorMessage {
                        Text(message).font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .confirmationDialog("End this ride?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Save Ride") { model.endRide() }
            Button("Discard Ride", role: .destructive) { model.discardRide() }
            Button("Keep Riding", role: .cancel) {}
        }
        .alert("Stopped riding?", isPresented: Binding(get: { model.smart.stopSuggestionPending && !confirmEnd },
                                                     set: { _ in })) {
            Button("Save Ride") { model.endRide() }
            Button("Keep Riding", role: .cancel) { model.smart.keepRiding() }
        } message: {
            Text("No riding movement for 3 minutes. This is an estimate; the ride keeps recording until you choose.")
        }
    }

    private func speedBlock(_ m: RideMetrics) -> some View {
        VStack(spacing: 0) {
            if m.state == .paused {
                Text("PAUSED")
                    .font(.headline)
                    .foregroundStyle(.yellow)
            }
            Text(m.state == .paused ? "--" : RideFormat.speed(m.currentSpeed))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(isLuminanceReduced ? .secondary : .primary)
                .accessibilityLabel("Speed \(RideFormat.speed(m.currentSpeed)) miles per hour, GPS estimate")
            HStack(spacing: 4) {
                Circle().fill(gpsColor(m.gps)).frame(width: 7, height: 7)
                Text("MPH · GPS EST.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("GPS \(m.gps.rawValue)")
        }
    }

    private func statsGrid(_ m: RideMetrics) -> some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                MetricTile(title: "TIME", value: RideFormat.duration(m.activeDuration))
                MetricTile(title: "DIST", value: RideFormat.distance(m.distanceMeters))
            }
            GridRow {
                MetricTile(title: "AVG MPH", value: RideFormat.speed(m.averageSpeed))
                MetricTile(title: "MAX MPH", value: RideFormat.speed(m.maxSpeed))
            }
        }
    }

    private func controls(_ m: RideMetrics) -> some View {
        HStack(spacing: 8) {
            if m.state == .paused {
                Button { model.resume() } label: {
                    Image(systemName: "play.fill").font(.title3).frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(.green)
                .accessibilityLabel("Resume ride")
            } else {
                Button { model.pause() } label: {
                    Image(systemName: "pause.fill").font(.title3).frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(.yellow)
                .accessibilityLabel("Pause ride")
            }
            Button { confirmEnd = true } label: {
                Image(systemName: "stop.fill").font(.title3).frame(maxWidth: .infinity, minHeight: 44)
            }
            .tint(.red)
            .accessibilityLabel("End ride")
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 4)
    }

    private func gpsColor(_ s: GPSStatus) -> Color {
        switch s {
        case .good: return .green
        case .fair: return .yellow
        case .searching: return .gray
        case .lost: return .red
        case .off: return .gray
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
