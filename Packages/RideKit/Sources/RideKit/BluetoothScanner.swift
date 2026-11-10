#if canImport(CoreBluetooth)
import Foundation
import CoreBluetooth
import Observation

/// One advertising device. The raw name lives in memory only, for masking on screen; it is
/// never written to disk or sent anywhere.
public struct DiscoveredDevice: Identifiable, Equatable, Sendable {
    /// CoreBluetooth's identifier: random per device pair, not the scooter's serial.
    public let id: UUID
    public var name: String?
    public var rssi: Int
    public var serviceUUIDs: [String]
    public var companyID: UInt16?
    public var txPower: Int?
    public var isConnectable: Bool?
    public var lastSeen: Date

    public var displayName: String { DeviceNameMask.display(name) }
}

public struct StandardReading: Identifiable, Equatable, Sendable {
    public var id: String { characteristic }
    public var characteristic: String
    public var name: String
    public var value: String
}

/// Bluetooth discovery that only acts when asked.
///
/// - Scans only after `startScan()`, and stops by itself after `duration`.
/// - Connects only from `readStandardInfo(of:)`, reads the allowed Device Information and
///   Battery values, then disconnects. It never writes and never subscribes to notifications.
/// - No background scanning: the apps call `stopScan()` when they leave the screen.
@MainActor
@Observable
public final class BluetoothScanner: NSObject {
    public enum State: Equatable, Sendable {
        case idle
        case unavailable(String)
        case scanning
        case reading(UUID)
    }

    public private(set) var state: State = .idle
    public private(set) var devices: [UUID: DiscoveredDevice] = [:]
    public private(set) var readings: [UUID: [StandardReading]] = [:]
    public private(set) var readMessages: [UUID: String] = [:]
    /// Called for every advertisement while scanning (the watch's start suggestion uses it).
    @ObservationIgnored public var onSighting: ((DiscoveredDevice) -> Void)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var scanDuration: TimeInterval = 20
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var pendingReads = 0
    @ObservationIgnored private var pendingServiceDiscoveries = 0
    @ObservationIgnored private var readTimeout: Task<Void, Never>?

    public override init() { super.init() }

    /// Devices sorted by signal, strongest first.
    public var sortedDevices: [DiscoveredDevice] { devices.values.sorted { $0.rssi > $1.rssi } }

    public func startScan(duration: TimeInterval = 20) {
        scanDuration = duration
        wantsScan = true
        guard let central else {
            // Creating the manager is what shows the Bluetooth permission prompt, so it waits
            // for this explicit action.
            self.central = CBCentralManager(delegate: self, queue: nil,
                                            options: [CBCentralManagerOptionShowPowerAlertKey: false])
            return   // scanning begins in centralManagerDidUpdateState
        }
        beginScanIfReady(central)
    }

    public func stopScan() {
        wantsScan = false
        stopTask?.cancel()
        stopTask = nil
        central?.stopScan()
        if state == .scanning { state = .idle }
    }

    /// Connects to one device the user picked, reads the allowed standard values, disconnects.
    public func readStandardInfo(of id: UUID) {
        guard let central, central.state == .poweredOn,
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else {
            readMessages[id] = "Device not available. Scan again with it nearby."
            return
        }
        stopScan()
        readings[id] = []
        readMessages[id] = "Connecting…"
        state = .reading(id)
        peripheral = p
        p.delegate = self
        central.connect(p)
        readTimeout?.cancel()
        readTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finishRead(id, message: "Timed out.")
        }
    }

    public func cancelRead() {
        if case .reading(let id) = state { finishRead(id, message: "Cancelled.") }
    }

    private func beginScanIfReady(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            guard wantsScan else { return }
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            state = .scanning
            stopTask?.cancel()
            let duration = scanDuration
            stopTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.stopScan()
            }
        case .unauthorized:
            state = .unavailable("Bluetooth access is off for ScooterRide. Turn it on in Settings > Privacy & Security > Bluetooth.")
        case .poweredOff:
            state = .unavailable("Bluetooth is off.")
        case .unsupported:
            state = .unavailable("This device doesn't support Bluetooth scanning.")
        default:
            break   // .unknown / .resetting: wait for the next update
        }
    }

    private func finishRead(_ id: UUID, message: String?) {
        readTimeout?.cancel()
        readTimeout = nil
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        pendingReads = 0
        pendingServiceDiscoveries = 0
        if let message { readMessages[id] = message }
        if state == .reading(id) { state = .idle }
    }

    private func record(_ reading: StandardReading, for id: UUID) {
        var list = readings[id] ?? []
        list.removeAll { $0.characteristic == reading.characteristic }
        list.append(reading)
        readings[id] = list.sorted { $0.name < $1.name }
    }
}

extension BluetoothScanner: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { self.beginScanIfReady(central) }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let company = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).flatMap(ManufacturerData.companyID)
        let tx = (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            guard rssi < 0 else { return }   // 127 means "unavailable"
            var d = self.devices[id] ?? DiscoveredDevice(id: id, name: name, rssi: rssi, serviceUUIDs: [],
                                                         companyID: nil, txPower: nil, isConnectable: nil, lastSeen: Date())
            d.name = name ?? d.name
            d.rssi = rssi
            d.serviceUUIDs = Array(Set(d.serviceUUIDs + services)).sorted()
            d.companyID = company ?? d.companyID
            d.txPower = tx ?? d.txPower
            d.isConnectable = connectable ?? d.isConnectable
            d.lastSeen = Date()
            self.devices[id] = d
            self.onSighting?(d)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        MainActor.assumeIsolated {
            self.readMessages[id] = "Reading standard information…"
            peripheral.discoverServices(StandardReads.services.map { CBUUID(string: $0) })
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                           error: Error?) {
        let id = peripheral.identifier
        let message = "Couldn't connect: \(error?.localizedDescription ?? "unknown error")"
        MainActor.assumeIsolated { self.finishRead(id, message: message) }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                           error: Error?) {
        let id = peripheral.identifier
        MainActor.assumeIsolated {
            if self.state == .reading(id) { self.finishRead(id, message: "Disconnected before reading finished.") }
        }
    }
}

extension BluetoothScanner: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let id = peripheral.identifier
        MainActor.assumeIsolated {
            let services = peripheral.services ?? []
            if services.isEmpty {
                self.finishRead(id, message: "No standard Device Information or Battery service. Nothing else is read.")
                return
            }
            self.pendingServiceDiscoveries = services.count
            for s in services {
                peripheral.discoverCharacteristics(
                    StandardReads.characteristics.map { CBUUID(string: $0) }, for: s)
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                       error: Error?) {
        let id = peripheral.identifier
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] where StandardReads.isAllowed(characteristic: c.uuid.uuidString) {
                if c.properties.contains(.read) {
                    self.pendingReads += 1
                    peripheral.readValue(for: c)
                } else {
                    let name = BluetoothNames.characteristicName(c.uuid.uuidString) ?? c.uuid.uuidString
                    self.record(StandardReading(characteristic: BluetoothNames.normalize(c.uuid.uuidString),
                                                name: name, value: "Not readable"), for: id)
                }
            }
            self.pendingServiceDiscoveries = max(0, self.pendingServiceDiscoveries - 1)
            if self.pendingReads == 0, self.pendingServiceDiscoveries == 0 {
                self.finishRead(id, message: (self.readings[id] ?? []).isEmpty ? "No standard values available." : "Done.")
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        let id = peripheral.identifier
        let uuid = characteristic.uuid.uuidString
        let value = characteristic.value
        let errorText = error?.localizedDescription
        MainActor.assumeIsolated {
            let name = BluetoothNames.characteristicName(uuid) ?? uuid
            let text = errorText.map { "Read failed: \($0)" }
                ?? value.map { StandardReads.describe(characteristic: uuid, value: $0) } ?? "Empty"
            self.record(StandardReading(characteristic: BluetoothNames.normalize(uuid), name: name, value: text), for: id)
            self.pendingReads = max(0, self.pendingReads - 1)
            if self.pendingReads == 0, self.pendingServiceDiscoveries == 0 { self.finishRead(id, message: "Done.") }
        }
    }
}
#endif
