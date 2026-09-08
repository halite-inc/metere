//
//  BluetoothBatteryManager.swift
//  metere
//

import Foundation
import IOBluetooth

public struct DeviceBatteryInfo: Equatable, Sendable {
    public let level: Int // 0 to 100
    public let leftLevel: Int?
    public let rightLevel: Int?
    public let caseLevel: Int?

    public init(
        level: Int,
        leftLevel: Int? = nil,
        rightLevel: Int? = nil,
        caseLevel: Int? = nil
    ) {
        self.level = min(max(level, 0), 100)
        self.leftLevel = leftLevel.map { min(max($0, 0), 100) }
        self.rightLevel = rightLevel.map { min(max($0, 0), 100) }
        self.caseLevel = caseLevel.map { min(max($0, 0), 100) }
    }

    public var sfSymbolName: String {
        if level >= 90 { return "battery.100" }
        if level >= 65 { return "battery.75" }
        if level >= 40 { return "battery.50" }
        if level >= 15 { return "battery.25" }
        return "battery.0"
    }

    public var formattedText: String {
        if let left = leftLevel, let right = rightLevel {
            return "L \(left)% · R \(right)%"
        }
        return "\(level)%"
    }
}

public final class BluetoothBatteryManager: @unchecked Sendable {
    public static let shared = BluetoothBatteryManager()

    private init() {}

    public static func normalizeMACAddress(from uid: String) -> String {
        uid.replacingOccurrences(of: ":output", with: "", options: .caseInsensitive)
           .replacingOccurrences(of: ":input", with: "", options: .caseInsensitive)
           .lowercased()
           .replacingOccurrences(of: ":", with: "-")
    }

    /// Retrieves battery information for a specified audio device by MAC address or name
    public func getBatteryInfo(for device: AudioDevice) -> DeviceBatteryInfo? {
        guard device.isBluetoothHeadphone else { return nil }

        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }

        // Normalize device MAC address from UID (handles both "74-D7-13-30-0D-89:output" and "74:d7:13:30:0d:89:output")
        let cleanUID = BluetoothBatteryManager.normalizeMACAddress(from: device.uid)
        let targetName = device.name.lowercased()

        for btDevice in paired where btDevice.isConnected() {
            let addr = btDevice.addressString?.lowercased().replacingOccurrences(of: ":", with: "-") ?? ""
            let name = btDevice.nameOrAddress?.lowercased() ?? ""

            let isMatch = (!cleanUID.isEmpty && addr == cleanUID) ||
                          (!targetName.isEmpty && (name.contains(targetName) || targetName.contains(name)))

            if isMatch {
                return extractBattery(from: btDevice)
            }
        }

        return nil
    }

    private func extractBattery(from device: IOBluetoothDevice) -> DeviceBatteryInfo? {
        let single = (device.value(forKey: "batteryPercentSingle") as? Int) ?? 0
        let left = (device.value(forKey: "batteryPercentLeft") as? Int) ?? 0
        let right = (device.value(forKey: "batteryPercentRight") as? Int) ?? 0
        let caseP = (device.value(forKey: "batteryPercentCase") as? Int) ?? 0
        let combined = (device.value(forKey: "batteryPercentCombined") as? Int) ?? 0
        let headset = (device.value(forKey: "headsetBatteryPercent") as? Int) ?? 0

        // In Apple HFP Bluetooth protocol, values <= 10 represent 10% steps (1 = 10%, 10 = 100%)
        func normalize(_ val: Int) -> Int {
            if val <= 0 { return 0 }
            if val <= 10 { return val * 10 }
            return min(val, 100)
        }

        let normSingle = normalize(single)
        let normCombined = normalize(combined)
        let normHeadset = normalize(headset)
        let normLeft = left > 0 ? normalize(left) : nil
        let normRight = right > 0 ? normalize(right) : nil
        let normCase = caseP > 0 ? normalize(caseP) : nil

        var overallLevel = 0
        if normSingle > 0 {
            overallLevel = normSingle
        } else if normCombined > 0 {
            overallLevel = normCombined
        } else if normHeadset > 0 {
            overallLevel = normHeadset
        } else if let l = normLeft, let r = normRight {
            overallLevel = (l + r) / 2
        } else if let l = normLeft {
            overallLevel = l
        } else if let r = normRight {
            overallLevel = r
        }

        guard overallLevel > 0 else { return nil }

        return DeviceBatteryInfo(
            level: overallLevel,
            leftLevel: normLeft,
            rightLevel: normRight,
            caseLevel: normCase
        )
    }
}
