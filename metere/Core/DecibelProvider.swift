//
//  DecibelProvider.swift
//  metere
//

import Foundation
import SwiftUI

// MARK: - Calibration Methodology

public enum CalibrationMethodology: Codable, Equatable, Sendable {
    case laboratoryCouplerIEC60318_4
    case calibratedAcousticMeasurement
    case electromechanicalSensitivityModel
    case other(String)

    public var displayName: String {
        switch self {
        case .laboratoryCouplerIEC60318_4:
            return "IEC 60318-4 Ear Simulator Coupler"
        case .calibratedAcousticMeasurement:
            return "Calibrated Acoustic Measurement"
        case .electromechanicalSensitivityModel:
            return "Electromechanical Impedance & Sensitivity Model"
        case .other(let name):
            return name
        }
    }
}

// MARK: - Empirical Calibration Point

public struct EmpiricalCalibrationPoint: Codable, Equatable, Sendable, Comparable {
    public let volume: Float // 0...1
    public let dbfs: Double  // e.g. -12.0
    public let measuredSPL: Double // e.g. 94.0 dBA

    public init(volume: Float, dbfs: Double, measuredSPL: Double) {
        self.volume = min(max(volume, 0.0), 1.0)
        self.dbfs = dbfs
        self.measuredSPL = measuredSPL
    }

    public static func < (lhs: EmpiricalCalibrationPoint, rhs: EmpiricalCalibrationPoint) -> Bool {
        lhs.volume < rhs.volume
    }
}

// MARK: - Acoustic Calibration Record

public struct AcousticCalibrationRecord: Codable, Equatable, Sendable {
    public let deviceUID: String
    public let deviceModel: String
    public let referenceSPL: Double
    public let calibratedVolume: Float
    public let calibratedDBFS: Double
    public let supportedVolumeTolerance: Float
    public let supportedDBFSTolerance: Double
    public let methodology: CalibrationMethodology
    public let uncertaintyDB: Double
    public let timestamp: Date
    public let isModelLevelOnly: Bool
    public var empiricalPoints: [EmpiricalCalibrationPoint]

    public init(
        deviceUID: String,
        deviceModel: String,
        referenceSPL: Double,
        calibratedVolume: Float,
        calibratedDBFS: Double,
        supportedVolumeTolerance: Float = 0.02,
        supportedDBFSTolerance: Double = 2.0,
        methodology: CalibrationMethodology = .calibratedAcousticMeasurement,
        uncertaintyDB: Double = 2.0,
        timestamp: Date = Date(),
        isModelLevelOnly: Bool = false,
        empiricalPoints: [EmpiricalCalibrationPoint] = []
    ) {
        self.deviceUID = deviceUID
        self.deviceModel = deviceModel
        self.referenceSPL = referenceSPL
        self.calibratedVolume = calibratedVolume
        self.calibratedDBFS = calibratedDBFS
        self.supportedVolumeTolerance = supportedVolumeTolerance
        self.supportedDBFSTolerance = supportedDBFSTolerance
        self.methodology = methodology
        self.uncertaintyDB = uncertaintyDB
        self.timestamp = timestamp
        self.isModelLevelOnly = isModelLevelOnly
        self.empiricalPoints = empiricalPoints
    }

    /// Rejects obviously invalid, unphysical, or corrupt calibration data
    public func isValidData() -> Bool {
        guard referenceSPL >= 30.0 && referenceSPL <= 130.0 else { return false }
        guard uncertaintyDB > 0.0 else { return false }
        guard calibratedVolume >= 0.0 && calibratedVolume <= 1.0 else { return false }
        guard supportedVolumeTolerance >= 0.0 else { return false }
        guard supportedDBFSTolerance >= 0.0 else { return false }
        guard !deviceUID.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !deviceModel.trimmingCharacters(in: .whitespaces).isEmpty else { return false }

        for pt in empiricalPoints {
            guard pt.measuredSPL >= 30.0 && pt.measuredSPL <= 130.0 else { return false }
            guard pt.volume >= 0.0 && pt.volume <= 1.0 else { return false }
        }

        return true
    }

    /// Determines if this calibration record applies to the given audio device
    public func matches(device: AudioDevice) -> (matches: Bool, isModelLevel: Bool) {
        let cleanDevUID = device.uid.components(separatedBy: ":").first?.lowercased().replacingOccurrences(of: ":", with: "-") ?? ""
        let cleanCalUID = deviceUID.components(separatedBy: ":").first?.lowercased().replacingOccurrences(of: ":", with: "-") ?? ""

        // Exact device UID / MAC address match
        if !cleanCalUID.isEmpty && cleanCalUID == cleanDevUID {
            return (true, isModelLevelOnly)
        }

        // Model-level match only if explicitly declared
        if isModelLevelOnly {
            let targetModel = deviceModel.lowercased().trimmingCharacters(in: .whitespaces)
            let currentName = device.name.lowercased().trimmingCharacters(in: .whitespaces)
            if !targetModel.isEmpty && (currentName == targetModel || currentName.contains(targetModel)) {
                return (true, true)
            }
        }

        return (false, false)
    }
}

// MARK: - Wired Headphone Electromechanical Physics Calculator

public enum DACPreset: String, CaseIterable, Identifiable, Sendable {
    case macBookProHighGain = "MacBook Pro 3.5mm (High Impedance ≥150Ω, 3.0 Vrms)"
    case macBookProStandard = "MacBook Pro 3.5mm (Standard <150Ω, 1.25 Vrms)"
    case appleUSBCDaq = "Apple USB-C to 3.5mm Adapter (1.0 Vrms)"
    case standardDAC = "Standard External DAC / Audio Interface (2.0 Vrms)"
    case custom = "Custom Voltage Output"

    public var id: String { rawValue }

    public var maxOutputVoltageVrms: Double {
        switch self {
        case .macBookProHighGain: return 3.0
        case .macBookProStandard: return 1.25
        case .appleUSBCDaq: return 1.0
        case .standardDAC: return 2.0
        case .custom: return 1.0
        }
    }

    public var outputImpedanceOhms: Double {
        switch self {
        case .macBookProHighGain, .macBookProStandard: return 0.5
        case .appleUSBCDaq: return 0.9
        case .standardDAC: return 1.0
        case .custom: return 0.5
        }
    }
}

public enum SensitivityUnit: String, CaseIterable, Identifiable, Sendable {
    case dbPerMilliwatt = "dB / mW"
    case dbPerVolt = "dB / Vrms"

    public var id: String { rawValue }
}

public struct WiredHeadphonePhysicsCalculator: Sendable {
    /// Calculates theoretical maximum SPL (at full volume 1.0 and 0 dBFS)
    public static func calculateMaxSPL(
        vrms: Double,
        outputImpedance: Double = 0.5,
        headphoneImpedance: Double,
        sensitivity: Double,
        unit: SensitivityUnit
    ) -> Double {
        guard headphoneImpedance > 0, vrms > 0 else { return 0 }
        let deliveredVoltage = vrms * (headphoneImpedance / (headphoneImpedance + outputImpedance))

        switch unit {
        case .dbPerMilliwatt:
            let powerMW = (deliveredVoltage * deliveredVoltage / headphoneImpedance) * 1000.0
            guard powerMW > 0 else { return 0 }
            return sensitivity + 10.0 * log10(powerMW)
        case .dbPerVolt:
            guard deliveredVoltage > 0 else { return 0 }
            return sensitivity + 20.0 * log10(deliveredVoltage)
        }
    }

    /// Generates multi-point empirical calibration points and a valid AcousticCalibrationRecord
    public static func generateCalibrationRecord(
        deviceUID: String,
        deviceModel: String,
        vrms: Double,
        outputImpedance: Double = 0.5,
        headphoneImpedance: Double,
        sensitivity: Double,
        unit: SensitivityUnit
    ) -> AcousticCalibrationRecord {
        let maxSPL = calculateMaxSPL(
            vrms: vrms,
            outputImpedance: outputImpedance,
            headphoneImpedance: headphoneImpedance,
            sensitivity: sensitivity,
            unit: unit
        )

        // Generate points for volume 0.30 ... 0.80 using macOS quadratic taper
        // macOS volume slider attenuation: SPL(v) = maxSPL + 40 * log10(v)
        let volumeSteps: [Float] = [0.30, 0.40, 0.50, 0.60, 0.70, 0.80]
        var points: [EmpiricalCalibrationPoint] = []

        for v in volumeSteps {
            let splAtVol = max(30.0, min(120.0, maxSPL + 40.0 * log10(Double(v))))
            points.append(EmpiricalCalibrationPoint(
                volume: v,
                dbfs: -12.0,
                measuredSPL: round(splAtVol * 10.0) / 10.0
            ))
        }

        let refSPLAt50 = max(30.0, min(120.0, maxSPL + 40.0 * log10(0.50)))

        return AcousticCalibrationRecord(
            deviceUID: deviceUID,
            deviceModel: deviceModel,
            referenceSPL: round(refSPLAt50 * 10.0) / 10.0,
            calibratedVolume: 0.50,
            calibratedDBFS: -12.0,
            supportedVolumeTolerance: 0.03,
            supportedDBFSTolerance: 2.0,
            methodology: .electromechanicalSensitivityModel,
            uncertaintyDB: 3.0,
            timestamp: Date(),
            isModelLevelOnly: false,
            empiricalPoints: points
        )
    }
}

// MARK: - Acoustic SPL Status

public enum AcousticSPLStatus: Equatable, Sendable {
    case notMeasured(reason: String)
    case calibrated(splDBA: Double, uncertaintyDB: Double, isModelLevel: Bool)

    public var isCalibrated: Bool {
        if case .calibrated = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .notMeasured:
            return "Not measured"
        case .calibrated(let dba, let unc, _):
            return String(format: "%.1f dBA ±%.1f dB", dba, unc)
        }
    }

    public var reasonText: String? {
        switch self {
        case .notMeasured(let reason):
            return reason
        case .calibrated(_, _, let isModelLevel):
            return isModelLevel ? "Model-level estimate" : "Device-specific calibration"
        }
    }
}

// MARK: - WHO Exposure Status

public enum WHOExposureStatus: Equatable, Sendable {
    case unavailable(reason: String)
    case evaluated(dosePercentage: Double, allowanceHours: Double, uncertaintyDB: Double)

    public var isAvailable: Bool {
        if case .evaluated = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .unavailable:
            return "Unavailable"
        case .evaluated(let dose, _, _):
            return String(format: "%.1f%%", dose)
        }
    }

    public var reasonText: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .evaluated(_, let allowance, let unc):
            return String(format: "Allowance: %.1fh · Cal. uncertainty ±%.1f dB", allowance, unc)
        }
    }
}

// MARK: - Decibel & Exposure Provider Protocol

public protocol DecibelProvider: AnyObject, Sendable {
    func digitalAttenuationDBFS(volumeScalar: Float) -> Double?

    func estimateAcousticSPL(
        currentVolume: Float,
        currentDBFS: Double?,
        isPlaying: Bool,
        device: AudioDevice?,
        calibration: AcousticCalibrationRecord?
    ) -> AcousticSPLStatus

    func evaluateWHOExposure(
        splStatus: AcousticSPLStatus,
        activeListeningSeconds: TimeInterval
    ) -> WHOExposureStatus
}

// MARK: - Standard Decibel & Exposure Provider

public final class StandardDecibelProvider: DecibelProvider, @unchecked Sendable {
    public static let shared = StandardDecibelProvider()

    public init() {}

    /// Computes measurable digital attenuation in dBFS matching macOS quadratic slider taper.
    /// Note: dBFS is strictly digital signal amplitude, NOT acoustic sound pressure (dBA SPL).
    public func digitalAttenuationDBFS(volumeScalar: Float) -> Double? {
        guard volumeScalar > 0.001 else {
            return nil // Muted / zero signal
        }
        let clamped = min(max(Double(volumeScalar), 0.001), 1.0)
        // macOS volume slider maps to digital gain via quadratic taper (gain = scalar^2)
        // dBFS = 20 * log10(scalar^2) = 40 * log10(scalar)
        let dbfs = 40.0 * log10(clamped)
        return round(dbfs * 10.0) / 10.0
    }

    /// Validates operating envelope and estimates Acoustic SPL only when conditions match calibration.
    /// Strictly refuses to extrapolate across volume or digital levels without empirical data.
    public func estimateAcousticSPL(
        currentVolume: Float,
        currentDBFS: Double?,
        isPlaying: Bool,
        device: AudioDevice?,
        calibration: AcousticCalibrationRecord?
    ) -> AcousticSPLStatus {
        // 1. Is audio actively playing?
        guard isPlaying else {
            return .notMeasured(reason: "No audio playing")
        }

        // 2. Is there an active output device?
        guard let device = device else {
            return .notMeasured(reason: "No device connected")
        }

        // 3. Is there a calibration record?
        guard let cal = calibration else {
            return .notMeasured(reason: "Acoustic calibration required")
        }

        // 4. Does calibration match the device identity?
        let matchResult = cal.matches(device: device)
        guard matchResult.matches else {
            return .notMeasured(reason: "Acoustic calibration required")
        }

        // 5. Is the calibration data physically valid?
        guard cal.isValidData() else {
            return .notMeasured(reason: "Invalid calibration data")
        }

        // 6. Check if multi-point empirical calibration is available
        let sortedPoints = cal.empiricalPoints.sorted()
        if sortedPoints.count >= 2 {
            // Must have digital level available
            guard let dbfs = currentDBFS else {
                return .notMeasured(reason: "Insufficient calibration data")
            }

            let minVol = sortedPoints.first!.volume
            let maxVol = sortedPoints.last!.volume

            // Strict envelope check: REFUSE to extrapolate outside measured range
            guard currentVolume >= (minVol - cal.supportedVolumeTolerance) &&
                  currentVolume <= (maxVol + cal.supportedVolumeTolerance) else {
                return .notMeasured(reason: "Insufficient calibration data (Operating conditions outside calibrated envelope)")
            }

            // Find surrounding points for piecewise linear interpolation
            var interpolatedSPL: Double? = nil
            for i in 0..<(sortedPoints.count - 1) {
                let p1 = sortedPoints[i]
                let p2 = sortedPoints[i + 1]

                if currentVolume >= (p1.volume - cal.supportedVolumeTolerance) && currentVolume <= (p2.volume + cal.supportedVolumeTolerance) {
                    let range = p2.volume - p1.volume
                    let clampedVol = min(max(currentVolume, p1.volume), p2.volume)
                    let t = range > 0 ? Double((clampedVol - p1.volume) / range) : 0.0
                    let spl = p1.measuredSPL + t * (p2.measuredSPL - p1.measuredSPL)

                    // Expected digital level interpolated
                    let expectedDBFS = p1.dbfs + t * (p2.dbfs - p1.dbfs)
                    if abs(dbfs - expectedDBFS) <= cal.supportedDBFSTolerance {
                        interpolatedSPL = spl
                        break
                    }
                }
            }

            if let spl = interpolatedSPL {
                return .calibrated(
                    splDBA: round(spl * 10.0) / 10.0,
                    uncertaintyDB: cal.uncertaintyDB,
                    isModelLevel: matchResult.isModelLevel
                )
            } else {
                return .notMeasured(reason: "Insufficient calibration data (Operating conditions outside calibrated envelope)")
            }
        }

        // Single-point calibration: check exact volume envelope
        let volDiff = abs(currentVolume - cal.calibratedVolume)
        guard volDiff <= cal.supportedVolumeTolerance else {
            return .notMeasured(reason: "Insufficient calibration data (Operating conditions outside calibrated envelope)")
        }

        // Is current digital level available?
        guard let dbfs = currentDBFS else {
            return .notMeasured(reason: "Insufficient calibration data")
        }

        // Is current digital level inside the calibrated operating envelope?
        let dbfsDiff = abs(dbfs - cal.calibratedDBFS)
        guard dbfsDiff <= cal.supportedDBFSTolerance else {
            return .notMeasured(reason: "Insufficient calibration data (Operating conditions outside calibrated envelope)")
        }

        // All conditions met within the single-point operating envelope:
        return .calibrated(
            splDBA: cal.referenceSPL,
            uncertaintyDB: cal.uncertaintyDB,
            isModelLevel: matchResult.isModelLevel
        )
    }

    /// Evaluates WHO Safe-Listening Exposure Dose strictly from calibrated acoustic SPL and active playback duration.
    /// Reference model: WHO 80 dBA / 40 hours/week (~5.71 hours/day = 20,571 seconds at 80 dBA) with 3 dB exchange rate.
    public func evaluateWHOExposure(
        splStatus: AcousticSPLStatus,
        activeListeningSeconds: TimeInterval
    ) -> WHOExposureStatus {
        guard case .calibrated(let splDBA, let uncertaintyDB, _) = splStatus else {
            if case .notMeasured(let reason) = splStatus {
                return .unavailable(reason: reason)
            }
            return .unavailable(reason: "Acoustic calibration required")
        }

        // Daily allowance at 80 dBA = 40 hours / 7 days = 5.714 hours = 20,571 seconds
        let dailyReferenceSeconds: Double = 20571.4

        // 3 dB exchange rate: doubling sound energy halves safe duration allowance.
        // Factor = 10^((dBA - 80) / 10)
        let intensityFactor = pow(10.0, (splDBA - 80.0) / 10.0)
        let effectiveSeconds = activeListeningSeconds * intensityFactor
        let dosePercentage = (effectiveSeconds / dailyReferenceSeconds) * 100.0

        // Safe continuous hours at this specific calibrated SPL
        let allowanceHours = (dailyReferenceSeconds / intensityFactor) / 3600.0

        return .evaluated(
            dosePercentage: round(dosePercentage * 10.0) / 10.0,
            allowanceHours: round(allowanceHours * 10.0) / 10.0,
            uncertaintyDB: uncertaintyDB
        )
    }
}
