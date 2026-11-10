import Foundation

// Standard, publicly documented Bluetooth information only. ScooterRide assumes nothing about
// undocumented Segway characteristics: the E3 Pro's own data channel is a vendor UART that
// ScooterRide never opens.

public enum BluetoothNames {
    /// Bluetooth SIG base UUID; 16-bit ids expand to 0000XXXX-0000-1000-8000-00805F9B34FB.
    static let sigBaseSuffix = "-0000-1000-8000-00805F9B34FB"
    public static let nordicUARTService = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"

    static let services: [String: String] = [
        "1800": "Generic Access",
        "1801": "Generic Attribute",
        "180A": "Device Information",
        "180D": "Heart Rate",
        "180F": "Battery",
        "1812": "Human Interface Device",
        "1816": "Cycling Speed and Cadence",
        "1818": "Cycling Power",
        "1826": "Fitness Machine",
        nordicUARTService: "Nordic UART (vendor data channel, not used)",
    ]

    static let characteristics: [String: String] = [
        "2A00": "Device Name",
        "2A01": "Appearance",
        "2A19": "Battery Level",
        "2A23": "System ID",
        "2A24": "Model Number",
        "2A25": "Serial Number",
        "2A26": "Firmware Revision",
        "2A27": "Hardware Revision",
        "2A28": "Software Revision",
        "2A29": "Manufacturer Name",
        "2A50": "PnP ID",
        "6E400002-B5A3-F393-E0A9-E50E24DCCA9E": "Nordic UART RX (not used)",
        "6E400003-B5A3-F393-E0A9-E50E24DCCA9E": "Nordic UART TX (not used)",
    ]

    /// Assigned company identifiers ScooterRide recognizes (a short list; others show as hex).
    static let companies: [UInt16: String] = [
        0x0006: "Microsoft",
        0x004C: "Apple",
        0x0059: "Nordic Semiconductor",
        0x0075: "Samsung",
        0x00E0: "Google",
    ]

    /// Uppercases and shortens SIG-base 128-bit UUIDs to their 16-bit form.
    public static func normalize(_ uuid: String) -> String {
        let u = uuid.uppercased()
        if u.count == 36, u.hasPrefix("0000"), u.hasSuffix(sigBaseSuffix) {
            return String(u.dropFirst(4).prefix(4))
        }
        return u
    }

    public static func serviceName(_ uuid: String) -> String? { services[normalize(uuid)] }
    public static func characteristicName(_ uuid: String) -> String? { characteristics[normalize(uuid)] }
    public static func companyName(_ id: UInt16) -> String? { companies[id] }

    public static func describeService(_ uuid: String) -> String {
        serviceName(uuid) ?? "Unrecognized service \(normalize(uuid))"
    }

    public static func describeCompany(_ id: UInt16) -> String {
        let hex = String(format: "0x%04X", id)
        return companyName(id).map { "\($0) (\(hex))" } ?? "Company \(hex) (not in ScooterRide's list)"
    }
}

/// The only Bluetooth values ScooterRide reads, and only when the user taps "Read standard
/// info": Device Information and Battery Level. Never the Serial Number or System ID, never a
/// write, never a notification subscription.
public enum StandardReads {
    public static let services: [String] = ["180A", "180F"]
    public static let characteristics: Set<String> = ["2A19", "2A24", "2A26", "2A27", "2A28", "2A29", "2A50"]

    public static func isAllowed(characteristic uuid: String) -> Bool {
        characteristics.contains(BluetoothNames.normalize(uuid))
    }

    /// Human-readable value for an allowed characteristic.
    public static func describe(characteristic uuid: String, value: Data) -> String {
        switch BluetoothNames.normalize(uuid) {
        case "2A19":
            guard let level = value.first, level <= 100 else { return "Invalid battery value" }
            return "\(level)%"
        case "2A50":
            return PnPID(value).map(\.description) ?? "Invalid PnP ID (\(value.count) bytes)"
        default:
            let trimmed = value.prefix { $0 != 0 }
            if let s = String(data: trimmed, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
            return value.isEmpty ? "Empty" : value.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
    }
}

/// PnP ID (0x2A50): who made the Bluetooth part and which product it is. Seven bytes, little-endian.
public struct PnPID: Equatable, Sendable, CustomStringConvertible {
    public var vendorIDSource: UInt8
    public var vendorID: UInt16
    public var productID: UInt16
    public var productVersion: UInt16

    public init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 7 else { return nil }
        vendorIDSource = b[0]
        vendorID = UInt16(b[1]) | UInt16(b[2]) << 8
        productID = UInt16(b[3]) | UInt16(b[4]) << 8
        productVersion = UInt16(b[5]) | UInt16(b[6]) << 8
    }

    public var description: String {
        let source: String
        switch vendorIDSource {
        case 1: source = BluetoothNames.companyName(vendorID).map { "\($0), Bluetooth SIG id" } ?? "Bluetooth SIG id"
        case 2: source = "USB-IF id"
        default: source = "unknown id source \(vendorIDSource)"
        }
        return String(format: "Vendor 0x%04X (%@), product 0x%04X, version 0x%04X",
                      vendorID, source, productID, productVersion)
    }
}

/// Some devices, including this E3 Pro, advertise their serial number as their Bluetooth name.
/// Names that look like serial numbers are shown masked and never stored.
public enum DeviceNameMask {
    public static func looksLikeSerial(_ token: String) -> Bool {
        guard token.count >= 10, token.allSatisfy({ ($0.isASCII && $0.isNumber) || ($0.isASCII && $0.isUppercase) }) else {
            return false
        }
        return token.filter(\.isNumber).count >= 3 && token.filter(\.isLetter).count >= 2
    }

    public static func display(_ name: String?) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "Unnamed device" }
        return name.split(separator: " ", omittingEmptySubsequences: false).map { part -> String in
            let token = String(part)
            guard looksLikeSerial(token) else { return token }
            return "\(token.prefix(2))…\(token.suffix(4))"
        }.joined(separator: " ")
    }
}

public enum ManufacturerData {
    /// The company identifier at the start of manufacturer-specific advertising data.
    public static func companyID(_ data: Data) -> UInt16? {
        let b = [UInt8](data.prefix(2))
        guard b.count == 2 else { return nil }
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }
}
