#if canImport(SwiftUI) && canImport(CoreBluetooth)
import SwiftUI

/// Bluetooth discovery screen, shared by the iPhone and watch apps. Scans only when the
/// user taps Scan, and stops when the screen closes.
public struct BluetoothDiscoveryList: View {
    let scanner: BluetoothScanner
    let chosenID: UUID?
    let chosenLabel: String?
    let onChoose: ((DiscoveredDevice) -> Void)?
    let onForget: (() -> Void)?
    @State private var showUnnamed = false

    public init(scanner: BluetoothScanner, chosenID: UUID? = nil, chosenLabel: String? = nil,
                onChoose: ((DiscoveredDevice) -> Void)? = nil, onForget: (() -> Void)? = nil) {
        self.scanner = scanner
        self.chosenID = chosenID
        self.chosenLabel = chosenLabel
        self.onChoose = onChoose
        self.onForget = onForget
    }

    public var body: some View {
        List {
            Section {
                Button {
                    if scanner.state == .scanning { scanner.stopScan() } else { scanner.startScan() }
                } label: {
                    Label(scanner.state == .scanning ? "Stop Scanning" : "Scan",
                          systemImage: scanner.state == .scanning ? "stop.circle" : "antenna.radiowaves.left.and.right")
                }
                if case .unavailable(let message) = scanner.state {
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }
                Toggle("Show unnamed devices", isOn: $showUnnamed)
            } footer: {
                Text("Scans for 20 seconds when you tap Scan. Shows standard advertised information only. Names that look like serial numbers are masked and never stored.")
            }

            if let chosenLabel {
                Section("My scooter") {
                    Text(chosenLabel)
                    if let onForget { Button("Forget", role: .destructive, action: onForget) }
                }
            }

            Section("Nearby") {
                let shown = scanner.sortedDevices.filter { showUnnamed || $0.name != nil }
                if shown.isEmpty {
                    Text(scanner.state == .scanning ? "Scanning…" : "No devices yet. Tap Scan.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { device in
                    NavigationLink {
                        BluetoothDeviceDetail(scanner: scanner, deviceID: device.id, chosenID: chosenID, onChoose: onChoose)
                    } label: {
                        BluetoothDeviceRow(device: device, isChosen: device.id == chosenID)
                    }
                }
            }
        }
        .navigationTitle("Bluetooth")
        .onDisappear { scanner.stopScan() }
    }
}

struct BluetoothDeviceRow: View {
    let device: DiscoveredDevice
    let isChosen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if isChosen { Image(systemName: "scooter").foregroundStyle(.green) }
                Text(device.displayName).lineLimit(1)
            }
            Text("\(device.rssi) dBm\(device.serviceUUIDs.isEmpty ? "" : " · \(device.serviceUUIDs.count) service(s)")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One device: advertised information, plus an explicit, read-only "Read standard info".
public struct BluetoothDeviceDetail: View {
    let scanner: BluetoothScanner
    let deviceID: UUID
    let chosenID: UUID?
    let onChoose: ((DiscoveredDevice) -> Void)?

    public init(scanner: BluetoothScanner, deviceID: UUID, chosenID: UUID? = nil,
                onChoose: ((DiscoveredDevice) -> Void)? = nil) {
        self.scanner = scanner
        self.deviceID = deviceID
        self.chosenID = chosenID
        self.onChoose = onChoose
    }

    public var body: some View {
        if let d = scanner.devices[deviceID] {
            List {
                Section("Advertised") {
                    LabeledContent("Name", value: d.displayName)
                    LabeledContent("Signal", value: "\(d.rssi) dBm")
                    LabeledContent("Connectable", value: d.isConnectable.map { $0 ? "Yes" : "No" } ?? "Unknown")
                    LabeledContent("Transmit power", value: d.txPower.map { "\($0) dBm" } ?? "Not advertised")
                    LabeledContent("Maker", value: d.companyID.map(BluetoothNames.describeCompany) ?? "Not advertised")
                }
                Section("Advertised services") {
                    if d.serviceUUIDs.isEmpty { Text("None advertised").foregroundStyle(.secondary) }
                    ForEach(d.serviceUUIDs, id: \.self) { Text(BluetoothNames.describeService($0)) }
                }
                Section {
                    Button {
                        scanner.readStandardInfo(of: d.id)
                    } label: {
                        Label("Read standard info", systemImage: "info.circle")
                    }
                    .disabled(scanner.state == .reading(d.id))
                    if scanner.state == .reading(d.id) {
                        Button("Cancel", role: .cancel) { scanner.cancelRead() }
                    }
                    if let message = scanner.readMessages[d.id] {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(scanner.readings[d.id] ?? []) { r in
                        LabeledContent(r.name, value: r.value)
                    }
                } header: {
                    Text("Standard information")
                } footer: {
                    Text("Connects only when you tap, reads Device Information and Battery Level if the device offers them, then disconnects. Never writes, never reads the serial number, never changes settings.")
                }
                if let onChoose {
                    Section {
                        Button {
                            onChoose(d)
                        } label: {
                            Label(d.id == chosenID ? "This is my scooter" : "Use as my scooter",
                                  systemImage: d.id == chosenID ? "checkmark.circle.fill" : "scooter")
                        }
                        .disabled(d.id == chosenID)
                    } footer: {
                        Text("With Smart Detection on, ScooterRide can suggest a ride when this device is switched on nearby while the app is open.")
                    }
                }
            }
            .navigationTitle(d.displayName)
        } else {
            Text("This device is no longer listed. Scan again.")
                .foregroundStyle(.secondary)
        }
    }
}
#endif
