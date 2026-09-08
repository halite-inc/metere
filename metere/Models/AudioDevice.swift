//
//  AudioDevice.swift
//  metere
//

import Foundation
import CoreAudio

public enum AudioTransportType: String, Codable, Sendable {
    case bluetooth
    case bluetoothLE
    case builtIn
    case usb
    case displayPort
    case hdmi
    case airPlay
    case virtualDevice
    case unknown

    public static func from(rawType: UInt32) -> AudioTransportType {
        switch rawType {
        case kAudioDeviceTransportTypeBluetooth:
            return .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            return .bluetoothLE
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeDisplayPort:
            return .displayPort
        case kAudioDeviceTransportTypeHDMI:
            return .hdmi
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay
        case kAudioDeviceTransportTypeVirtual:
            return .virtualDevice
        default:
            return .unknown
        }
    }
}

public struct AudioDevice: Identifiable, Hashable, Codable, Sendable {
    public let id: UInt32
    public let uid: String
    public let name: String
    public let manufacturer: String?
    public let modelUID: String?
    public let transportType: AudioTransportType
    public let hasOutput: Bool

    public init(
        id: UInt32,
        uid: String,
        name: String,
        manufacturer: String? = nil,
        modelUID: String? = nil,
        transportType: AudioTransportType,
        hasOutput: Bool
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.manufacturer = manufacturer
        self.modelUID = modelUID
        self.transportType = transportType
        self.hasOutput = hasOutput
    }

    /// Determines whether this device represents Bluetooth headphones/earbuds.
    public var isBluetoothHeadphone: Bool {
        guard hasOutput else { return false }
        guard transportType == .bluetooth || transportType == .bluetoothLE else { return false }

        let lowerName = name.lowercased()

        // Exclude Bluetooth car audio or handsfree accessories if explicitly indicated
        if lowerName.contains("carplay") || lowerName.contains("hands-free car") {
            return false
        }

        // On macOS, personal Bluetooth audio devices with output streams are headphones/earbuds/headsets.
        return true
    }

    /// Best SF Symbol to represent this device
    public var sfSymbolName: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") {
            return "airpodsmax"
        } else if lower.contains("airpods pro") {
            return "airpodspro"
        } else if lower.contains("airpods") {
            return "airpods"
        } else if lower.contains("beats fit") || lower.contains("beats studio buds") {
            return "beats.earphones"
        } else if lower.contains("beats") {
            return "beats.headphones"
        } else if isBluetoothHeadphone {
            return "headphones"
        } else if transportType == .builtIn {
            return "laptopcomputer"
        } else {
            return "speaker.wave.2"
        }
    }
}
