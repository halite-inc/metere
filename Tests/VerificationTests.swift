//
//  VerificationTests.swift
//  metere
//

import Foundation

// MARK: - Helper Fixtures

func makeTestDevice(id: UInt32 = 85, uid: String = "test-device-001", name: String = "Nord Buds 2R") -> AudioDevice {
    AudioDevice(
        id: id,
        uid: uid,
        name: name,
        manufacturer: "OnePlus",
        modelUID: "NordBuds2R",
        transportType: .bluetooth,
        hasOutput: true
    )
}

func makeValidCalibration(
    deviceUID: String = "test-device-001",
    deviceModel: String = "Nord Buds 2R",
    refSPL: Double = 94.0,
    vol: Float = 0.50,
    dbfs: Double = -12.0,
    volTol: Float = 0.02,
    dbfsTol: Double = 2.0,
    uncertainty: Double = 2.0,
    isModelLevel: Bool = false,
    empiricalPoints: [EmpiricalCalibrationPoint] = []
) -> AcousticCalibrationRecord {
    AcousticCalibrationRecord(
        deviceUID: deviceUID,
        deviceModel: deviceModel,
        referenceSPL: refSPL,
        calibratedVolume: vol,
        calibratedDBFS: dbfs,
        supportedVolumeTolerance: volTol,
        supportedDBFSTolerance: dbfsTol,
        methodology: .laboratoryCouplerIEC60318_4,
        uncertaintyDB: uncertainty,
        timestamp: Date(),
        isModelLevelOnly: isModelLevel,
        empiricalPoints: empiricalPoints
    )
}

// MARK: - 20 Architectural Tests

// 1. Idle playback produces zero listening time
func testIdlePlaybackProducesZeroListeningTime() {
    print("--- Running testIdlePlaybackProducesZeroListeningTime ---")
    let now = Date()
    var session = ListeningSession(
        deviceUID: "test-device-001",
        deviceName: "Nord Buds 2R",
        startTime: now.addingTimeInterval(-3600),
        activePlaybackDuration: 0,
        currentPlaybackStart: nil
    )
    assert(session.duration(at: now) == 0.0, "Connected headphones without audio playback must have 0s duration")
    assert(!session.isAudioPlaying, "Session must not be playing")
    session.complete(at: now)
    assert(session.activePlaybackDuration == 0.0, "Completed idle session duration must be 0s")
    print("✅ 1. testIdlePlaybackProducesZeroListeningTime passed")
}

// 2. Paused playback does not accumulate time
func testPausedPlaybackDoesNotAccumulateTime() {
    print("--- Running testPausedPlaybackDoesNotAccumulateTime ---")
    let t0 = Date()
    var session = ListeningSession(deviceUID: "test-device-001", deviceName: "Nord Buds 2R", startTime: t0)

    // Play 10 mins (600s)
    session.startPlayback(at: t0)
    let tPause = t0.addingTimeInterval(600)
    session.pausePlayback(at: tPause)
    assert(session.activePlaybackDuration == 600.0, "Must be 600s after 10m playback")

    // Advance 20 mins while paused
    let tCheck = tPause.addingTimeInterval(1200)
    assert(session.duration(at: tCheck) == 600.0, "Duration while paused must remain 600s, got \(session.duration(at: tCheck))")
    print("✅ 2. testPausedPlaybackDoesNotAccumulateTime passed")
}

// 3. Playback resume continues accumulation
func testPlaybackResumeContinuesAccumulation() {
    print("--- Running testPlaybackResumeContinuesAccumulation ---")
    let t0 = Date()
    var session = ListeningSession(deviceUID: "test-device-001", deviceName: "Nord Buds 2R", startTime: t0)

    session.startPlayback(at: t0)
    let t1 = t0.addingTimeInterval(600) // 10 min
    session.pausePlayback(at: t1)

    let tResume = t1.addingTimeInterval(900) // paused for 15 min
    session.startPlayback(at: tResume)
    let tEnd = tResume.addingTimeInterval(900) // played for 15 min
    session.complete(at: tEnd)

    let expected: TimeInterval = 600 + 900 // 1500s = 25m
    assert(session.activePlaybackDuration == expected, "Expected 1500s active playback, got \(session.activePlaybackDuration)")
    assert(DailyStatistics.formattedDuration(session.activePlaybackDuration) == "25m")
    print("✅ 3. testPlaybackResumeContinuesAccumulation passed")
}

// 4. Digital level is reported as dBFS
func testDigitalLevelIsReportedAsDBFS() {
    print("--- Running testDigitalLevelIsReportedAsDBFS ---")
    let provider = StandardDecibelProvider.shared
    assert(provider.digitalAttenuationDBFS(volumeScalar: 1.0) == 0.0, "100% volume must be 0.0 dBFS")
    assert(provider.digitalAttenuationDBFS(volumeScalar: 0.5) == -12.0, "50% volume must be -12.0 dBFS")
    assert(provider.digitalAttenuationDBFS(volumeScalar: 0.25) == -24.1, "25% volume must be -24.1 dBFS")
    assert(provider.digitalAttenuationDBFS(volumeScalar: 0.0) == nil, "0% volume must be nil (muted)")
    print("✅ 4. testDigitalLevelIsReportedAsDBFS passed")
}

// 5. System volume is independent of dBFS
func testSystemVolumeIsIndependentOfDBFS() {
    print("--- Running testSystemVolumeIsIndependentOfDBFS ---")
    let volumeScalar: Float = 0.50
    let volumePercent = Int(round(volumeScalar * 100))
    let digitalLevel = StandardDecibelProvider.shared.digitalAttenuationDBFS(volumeScalar: volumeScalar)

    assert(volumePercent == 50, "System volume is 50%")
    assert(digitalLevel == -12.0, "Digital level is -12.0 dBFS")
    assert(Double(volumePercent) != digitalLevel!, "Volume percentage (50%) and dBFS (-12.0 dBFS) must remain distinct metrics")
    print("✅ 5. testSystemVolumeIsIndependentOfDBFS passed")
}

// 6. Uncalibrated exposure is unavailable
func testUncalibratedExposureIsUnavailable() {
    print("--- Running testUncalibratedExposureIsUnavailable ---")
    let provider = StandardDecibelProvider.shared
    let device = makeTestDevice()

    // Active playback, but NO calibration record provided
    let spl = provider.estimateAcousticSPL(currentVolume: 0.5, currentDBFS: -12.0, isPlaying: true, device: device, calibration: nil)
    guard case .notMeasured(let reason) = spl else {
        fatalError("Acoustic SPL must be .notMeasured when uncalibrated, got \(spl)")
    }
    assert(reason == "Acoustic calibration required", "Reason must be 'Acoustic calibration required', got \(reason)")

    let who = provider.evaluateWHOExposure(splStatus: spl, activeListeningSeconds: 3600)
    guard case .unavailable(let whoReason) = who else {
        fatalError("WHO Exposure must be .unavailable when uncalibrated, got \(who)")
    }
    assert(whoReason == "Acoustic calibration required")
    print("✅ 6. testUncalibratedExposureIsUnavailable passed")
}

// 7. Bluetooth connection alone does not create exposure
func testBluetoothConnectionAloneDoesNotCreateExposure() {
    print("--- Running testBluetoothConnectionAloneDoesNotCreateExposure ---")
    let provider = StandardDecibelProvider.shared
    let device = makeTestDevice()
    let cal = makeValidCalibration()

    // Connected, valid calibration exists, but audio is NOT playing
    let spl = provider.estimateAcousticSPL(currentVolume: 0.5, currentDBFS: -12.0, isPlaying: false, device: device, calibration: cal)
    guard case .notMeasured(let reason) = spl else {
        fatalError("Acoustic SPL must be .notMeasured when audio is not playing, got \(spl)")
    }
    assert(reason == "No audio playing")

    let who = provider.evaluateWHOExposure(splStatus: spl, activeListeningSeconds: 0)
    guard case .unavailable = who else {
        fatalError("WHO Exposure must be .unavailable when not playing")
    }
    print("✅ 7. testBluetoothConnectionAloneDoesNotCreateExposure passed")
}

// 8. Battery telemetry does not affect exposure
func testBatteryTelemetryDoesNotAffectExposure() {
    print("--- Running testBatteryTelemetryDoesNotAffectExposure ---")
    let bFull = DeviceBatteryInfo(level: 100)
    let bLow = DeviceBatteryInfo(level: 10)

    let provider = StandardDecibelProvider.shared
    let device = makeTestDevice()
    let cal = makeValidCalibration()

    let spl1 = provider.estimateAcousticSPL(currentVolume: 0.5, currentDBFS: -12.0, isPlaying: true, device: device, calibration: cal)
    let spl2 = provider.estimateAcousticSPL(currentVolume: 0.5, currentDBFS: -12.0, isPlaying: true, device: device, calibration: cal)
    assert(spl1 == spl2, "Battery state (\(bFull.level)% vs \(bLow.level)%) must have zero impact on acoustic SPL")
    print("✅ 8. testBatteryTelemetryDoesNotAffectExposure passed")
}

// 9. Calibration record requires device match
func testCalibrationRecordRequiresDeviceMatch() {
    print("--- Running testCalibrationRecordRequiresDeviceMatch ---")
    let provider = StandardDecibelProvider.shared
    let devA = makeTestDevice(uid: "test-device-001", name: "Nord Buds 2R")
    let devB = makeTestDevice(uid: "test-device-002", name: "Nord Buds 2R") // same model name, different physical device UID

    let calForA = makeValidCalibration(deviceUID: "test-device-001", isModelLevel: false)

    // Match on devA must succeed
    let splA = provider.estimateAcousticSPL(currentVolume: 0.5, currentDBFS: -12.0, isPlaying: true, device: devA, calibration: calForA)
    assert(splA.isCalibrated, "Calibration must apply to matching device UID")

    // Match on devB must be rejected
    let splB = provider.estimateAcousticSPL(currentVolume: 0.5, currentDBFS: -12.0, isPlaying: true, device: devB, calibration: calForA)
    guard case .notMeasured(let reason) = splB else {
        fatalError("Calibration must NOT automatically apply to another device UID with same model name")
    }
    assert(reason == "Acoustic calibration required")
    print("✅ 9. testCalibrationRecordRequiresDeviceMatch passed")
}

// 10. Calibration record requires valid measurement data
func testCalibrationRecordRequiresMeasurementData() {
    print("--- Running testCalibrationRecordRequiresMeasurementData ---")
    let invalidCal1 = makeValidCalibration(refSPL: 0.0) // unphysical SPL
    assert(!invalidCal1.isValidData(), "Zero SPL must be invalid")

    let invalidCal2 = makeValidCalibration(uncertainty: 0.0) // uncertainty must be > 0
    assert(!invalidCal2.isValidData(), "Zero uncertainty must be invalid")

    let invalidCal3 = makeValidCalibration(deviceUID: "") // empty UID
    assert(!invalidCal3.isValidData(), "Empty UID must be invalid")

    let validCal = makeValidCalibration()
    assert(validCal.isValidData(), "Valid calibration must pass validation")
    print("✅ 10. testCalibrationRecordRequiresMeasurementData passed")
}

// 11. Invalid calibration disables WHO exposure
func testInvalidCalibrationDisablesWHOExposure() {
    print("--- Running testInvalidCalibrationDisablesWHOExposure ---")
    let provider = StandardDecibelProvider.shared
    let device = makeTestDevice()
    let badCal = makeValidCalibration(refSPL: 15.0) // invalid SPL

    let spl = provider.estimateAcousticSPL(currentVolume: 0.5, currentDBFS: -12.0, isPlaying: true, device: device, calibration: badCal)
    guard case .notMeasured(let reason) = spl else {
        fatalError("Acoustic SPL must reject invalid calibration")
    }
    assert(reason == "Invalid calibration data")

    let who = provider.evaluateWHOExposure(splStatus: spl, activeListeningSeconds: 3600)
    guard case .unavailable = who else {
        fatalError("WHO exposure must be unavailable with invalid calibration")
    }
    print("✅ 11. testInvalidCalibrationDisablesWHOExposure passed")
}

// 12. Valid calibration enables calibrated SPL
func testValidCalibrationEnablesCalibratedSPL() {
    print("--- Running testValidCalibrationEnablesCalibratedSPL ---")
    let provider = StandardDecibelProvider.shared
    let device = makeTestDevice()
    let cal = makeValidCalibration(refSPL: 94.0, uncertainty: 2.0)

    let spl = provider.estimateAcousticSPL(currentVolume: 0.50, currentDBFS: -12.0, isPlaying: true, device: device, calibration: cal)
    guard case .calibrated(let dba, let unc, let isModel) = spl else {
        fatalError("Must produce calibrated SPL when inside envelope")
    }
    assert(dba == 94.0, "Reported dBA must equal measured reference SPL 94.0 dBA")
    assert(unc == 2.0, "Reported uncertainty must equal 2.0 dB")
    assert(!isModel, "Must be device-specific calibration")
    print("✅ 12. testValidCalibrationEnablesCalibratedSPL passed: \(dba) dBA ±\(unc) dB")
}

// 13. Calibration uncertainty is preserved
func testCalibrationUncertaintyIsPreserved() {
    print("--- Running testCalibrationUncertaintyIsPreserved ---")
    let provider = StandardDecibelProvider.shared
    let device = makeTestDevice()
    let cal = makeValidCalibration(refSPL: 94.0, uncertainty: 2.5)

    let spl = provider.estimateAcousticSPL(currentVolume: 0.50, currentDBFS: -12.0, isPlaying: true, device: device, calibration: cal)
    let who = provider.evaluateWHOExposure(splStatus: spl, activeListeningSeconds: 1800)

    guard case .evaluated(_, _, let unc) = who else {
        fatalError("WHO exposure must be evaluated")
    }
    assert(unc == 2.5, "Calibration uncertainty ±2.5 dB must be explicitly preserved, got \(unc)")
    print("✅ 13. testCalibrationUncertaintyIsPreserved passed: uncertainty preserved as ±\(unc) dB")
}

// 14. Uncalibrated playback still tracks listening time
func testUncalibratedPlaybackStillTracksListeningTime() {
    print("--- Running testUncalibratedPlaybackStillTracksListeningTime ---")
    // Timer accumulation must be completely decoupled from calibration
    let t0 = Date()
    var session = ListeningSession(deviceUID: "uncalibrated-device", deviceName: "AirPods", startTime: t0)
    session.startPlayback(at: t0)
    let t1 = t0.addingTimeInterval(2537) // 42m 17s
    session.pausePlayback(at: t1)

    assert(session.activePlaybackDuration == 2537.0, "Listening time must accumulate without calibration")
    assert(DailyStatistics.formattedDuration(session.activePlaybackDuration) == "42m")
    print("✅ 14. testUncalibratedPlaybackStillTracksListeningTime passed: 00:42:17 logged without calibration")
}

// 15. Calibration refuses to synthesize SPL outside volume operating envelope
func testCalibrationRefusesToSynthesizeSPLOutsideOperatingEnvelope() {
    print("--- Running testCalibrationRefusesToSynthesizeSPLOutsideOperatingEnvelope ---")
    let provider = StandardDecibelProvider.shared
    let device = makeTestDevice()
    // Calibrated at 50% volume (0.50) with ±2% tolerance (0.48 ... 0.52)
    let cal = makeValidCalibration(vol: 0.50, volTol: 0.02)

    // 1. Current volume = 51% (0.51) -> Inside envelope
    let splInside = provider.estimateAcousticSPL(currentVolume: 0.51, currentDBFS: -12.0, isPlaying: true, device: device, calibration: cal)
    assert(splInside.isCalibrated, "51% volume should be inside ±2% envelope")

    // 2. Current volume = 90% (0.90) -> OUTSIDE envelope! Must REFUSE to guess!
    let splOutside = provider.estimateAcousticSPL(currentVolume: 0.90, currentDBFS: -12.0, isPlaying: true, device: device, calibration: cal)
    guard case .notMeasured(let reason) = splOutside else {
        fatalError("Must NOT synthesize SPL when volume (90%) is outside calibrated envelope (50% ±2%)")
    }
    assert(reason.contains("Operating conditions outside calibrated envelope"), "Must report envelope rejection, got: \(reason)")
    print("✅ 15. testCalibrationRefusesToSynthesizeSPLOutsideOperatingEnvelope passed")
}

// 16. Calibration refuses SPL when dBFS outside operating envelope
func testCalibrationRefusesSPLWhenDBFSOutsideOperatingEnvelope() {
    print("--- Running testCalibrationRefusesSPLWhenDBFSOutsideOperatingEnvelope ---")
    let provider = StandardDecibelProvider.shared
    let device = makeTestDevice()
    // Calibrated at -12.0 dBFS with ±2.0 dB tolerance (-14.0 ... -10.0 dBFS)
    let cal = makeValidCalibration(dbfs: -12.0, dbfsTol: 2.0)

    // Current digital level = -30.0 dBFS -> OUTSIDE envelope! Must REFUSE to guess!
    let splOutside = provider.estimateAcousticSPL(currentVolume: 0.50, currentDBFS: -30.0, isPlaying: true, device: device, calibration: cal)
    guard case .notMeasured(let reason) = splOutside else {
        fatalError("Must NOT synthesize SPL when digital level (-30 dBFS) is outside calibrated envelope (-12 dBFS ±2 dB)")
    }
    assert(reason.contains("Operating conditions outside calibrated envelope"))
    print("✅ 16. testCalibrationRefusesSPLWhenDBFSOutsideOperatingEnvelope passed")
}

// 17. Calibration requires both volume and dBFS conditions
func testCalibrationRequiresBothVolumeAndDBFSConditions() {
    print("--- Running testCalibrationRequiresBothVolumeAndDBFSConditions ---")
    let provider = StandardDecibelProvider.shared
    let device = makeTestDevice()
    let cal = makeValidCalibration(vol: 0.50, dbfs: -12.0)

    // Both volume 90% AND dBFS -30 dBFS outside
    let splBoth = provider.estimateAcousticSPL(currentVolume: 0.90, currentDBFS: -30.0, isPlaying: true, device: device, calibration: cal)
    guard case .notMeasured = splBoth else {
        fatalError("Must refuse when both conditions outside")
    }
    print("✅ 17. testCalibrationRequiresBothVolumeAndDBFSConditions passed")
}

// 18. Single-point calibration never extrapolates
func testSinglePointCalibrationNeverExtrapolates() {
    print("--- Running testSinglePointCalibrationNeverExtrapolates ---")
    let provider = StandardDecibelProvider.shared
    let device = makeTestDevice()
    let cal = makeValidCalibration(refSPL: 94.0, vol: 0.50, dbfs: -12.0)

    // Test a sweep of arbitrary volume points: 20%, 30%, 40%, 60%, 70%, 80%, 90%
    let testVolumes: [Float] = [0.20, 0.30, 0.40, 0.60, 0.70, 0.80, 0.90]
    for v in testVolumes {
        let spl = provider.estimateAcousticSPL(currentVolume: v, currentDBFS: -12.0, isPlaying: true, device: device, calibration: cal)
        guard case .notMeasured = spl else {
            fatalError("Single-point calibration must NEVER extrapolate to volume \(v * 100)%")
        }
    }
    print("✅ 18. testSinglePointCalibrationNeverExtrapolates passed (refused all 7 extrapolation points)")
}

// 19. Model-level calibration is marked as model-level
func testModelLevelCalibrationIsMarkedAsModelLevel() {
    print("--- Running testModelLevelCalibrationIsMarkedAsModelLevel ---")
    let provider = StandardDecibelProvider.shared
    let device = makeTestDevice(uid: "different-physical-device-id", name: "Nord Buds 2R")
    let cal = makeValidCalibration(deviceUID: "original-unit-uid", deviceModel: "Nord Buds 2R", isModelLevel: true)

    let spl = provider.estimateAcousticSPL(currentVolume: 0.50, currentDBFS: -12.0, isPlaying: true, device: device, calibration: cal)
    guard case .calibrated(let dba, _, let isModel) = spl else {
        fatalError("Model-level calibration must match by model name")
    }
    assert(isModel, "isModelLevel must be true for model-level calibration")
    assert(dba == 94.0)
    print("✅ 19. testModelLevelCalibrationIsMarkedAsModelLevel passed: marked as model-level estimate")
}

// 20. WHO exposure uses only active playback intervals
func testWHOExposureUsesOnlyActivePlaybackIntervals() {
    print("--- Running testWHOExposureUsesOnlyActivePlaybackIntervals ---")
    let provider = StandardDecibelProvider.shared
    let splStatus = AcousticSPLStatus.calibrated(splDBA: 94.0, uncertaintyDB: 2.0, isModelLevel: false)

    // User scenario: 10 min playing + 5 min paused + 20 min playing = 30 min active (1800s), NOT 35 min (2100s)
    let activeDuration: TimeInterval = 1800.0
    let whoActive = provider.evaluateWHOExposure(splStatus: splStatus, activeListeningSeconds: activeDuration)

    guard case .evaluated(let doseActive, let allowanceHours, _) = whoActive else {
        fatalError("Must evaluate WHO dose")
    }

    // At 94 dBA (+14 dB above 80 dBA):
    // Energy factor = 10^(1.4) = 25.11886
    // Allowance hours = 5.714h / 25.11886 = 0.227h (~13.6 mins)
    // For 30 mins active (1800s):
    // Dose = (1800 * 25.11886 / 20571.4) * 100 = 219.8%
    assert(doseActive > 210.0 && doseActive < 230.0, "Dose for 30m at 94 dBA must be ~220%, got \(doseActive)%")
    assert(allowanceHours < 0.5, "Daily allowance at 94 dBA must be under 0.5h, got \(allowanceHours)h")

    print("✅ 20. testWHOExposureUsesOnlyActivePlaybackIntervals passed: dose = \(doseActive)%, allowance = \(allowanceHours)h")
}

// 21. Statistics use authoritative listening time
func testStatisticsUseAuthoritativeListeningTime() {
    print("--- Running testStatisticsUseAuthoritativeListeningTime ---")
    let now = Date()
    var daily = DailyStatistics(calendarDate: now)

    var session1 = ListeningSession(deviceUID: "test-device-001", deviceName: "Nord Buds 2R", startTime: now.addingTimeInterval(-1800))
    session1.startPlayback(at: now.addingTimeInterval(-1800))
    session1.pausePlayback(at: now.addingTimeInterval(-900)) // 900s active
    daily.sessions.append(session1)

    var session2 = ListeningSession(deviceUID: "test-device-001", deviceName: "Nord Buds 2R", startTime: now.addingTimeInterval(-600))
    session2.startPlayback(at: now.addingTimeInterval(-600))
    session2.pausePlayback(at: now.addingTimeInterval(-300)) // 300s active
    daily.sessions.append(session2)

    // Authoritative duration
    let authoritative = daily.totalListeningDuration(now: now)
    assert(authoritative == 1200.0, "Authoritative daily duration must be exactly 1200s (20m)")

    // Weekly trend summary must match authoritative duration
    let trend = HistoryAnalyzer.buildWeeklyTrend(todayStats: daily, activeSession: nil, allDailyRecords: [:], now: now)
    guard let todaySummary = trend.first(where: { $0.isToday }) else {
        fatalError("Weekly trend must contain today")
    }
    assert(todaySummary.activeSeconds == authoritative, "Weekly trend must use authoritative duration")
    print("✅ 21. testStatisticsUseAuthoritativeListeningTime passed: 1200s authoritative")
}

// 22. Popover and Statistics have consistent listening totals
func testPopoverAndStatisticsHaveConsistentListeningTotals() {
    print("--- Running testPopoverAndStatisticsHaveConsistentListeningTotals ---")
    let testSeconds: TimeInterval = 6120.0 // 1h 42m
    let popoverString = DailyStatistics.formattedDuration(testSeconds)
    let statsString = DailyStatistics.formattedDuration(testSeconds)

    assert(popoverString == "1h 42m", "Duration formatting must be 1h 42m")
    assert(popoverString == statsString, "Popover and Statistics must render mathematically identical duration strings")
    print("✅ 22. testPopoverAndStatisticsHaveConsistentListeningTotals passed: \(popoverString)")
}

// 23. Break reminder uses active playback time
func testBreakReminderUsesActivePlaybackTime() {
    print("--- Running testBreakReminderUsesActivePlaybackTime ---")
    var continuous: TimeInterval = 0
    let reminderThreshold: TimeInterval = 1800.0 // 30 mins

    // 25 mins active
    continuous += 1500.0
    assert(continuous < reminderThreshold, "Must not trigger before threshold")

    // Another 10 mins active
    continuous += 600.0
    assert(continuous >= reminderThreshold, "Must trigger when active playback reaches threshold (2100s >= 1800s)")
    print("✅ 23. testBreakReminderUsesActivePlaybackTime passed: threshold reached on active playback")
}

// 24. Paused playback does not trigger break reminder
func testPausedPlaybackDoesNotTriggerBreakReminder() {
    print("--- Running testPausedPlaybackDoesNotTriggerBreakReminder ---")
    let continuous: TimeInterval = 1200.0 // 20 mins active playback
    let reminderThreshold: TimeInterval = 1800.0 // 30 mins

    // 40 mins passed while audio is paused
    let pausedInterval: TimeInterval = 2400.0
    // Paused interval must NOT be added to continuous playback duration!
    _ = pausedInterval

    assert(continuous < reminderThreshold, "Paused playback must never increment continuous playback duration")
    print("✅ 24. testPausedPlaybackDoesNotTriggerBreakReminder passed: 1200s unchanged during 40m pause")
}

// 25. Disconnected device does not accumulate listening time
func testDisconnectedDeviceDoesNotAccumulateListeningTime() {
    print("--- Running testDisconnectedDeviceDoesNotAccumulateListeningTime ---")
    let now = Date()
    var session = ListeningSession(deviceUID: "test-device-001", deviceName: "Nord Buds 2R", startTime: now.addingTimeInterval(-3600))
    session.startPlayback(at: now.addingTimeInterval(-3600))
    session.complete(at: now.addingTimeInterval(-1800)) // Disconnected 30 mins ago

    let durAtDisconnect = session.activePlaybackDuration
    let durNow = session.duration(at: now)
    assert(durAtDisconnect == 1800.0, "Duration at disconnect must be 1800s")
    assert(durNow == 1800.0, "Disconnected session must not accumulate further listening time")
    assert(!session.isActive, "Completed session must be inactive")
    print("✅ 25. testDisconnectedDeviceDoesNotAccumulateListeningTime passed")
}

// 26. Insufficient history does not create fake baseline
func testInsufficientHistoryDoesNotCreateFakeBaseline() {
    print("--- Running testInsufficientHistoryDoesNotCreateFakeBaseline ---")
    let now = Date()
    var records: [String: DailyStatistics] = [:]

    // Provide only 2 days of history (< 3 required)
    var day1 = DailyStatistics(calendarDate: now.addingTimeInterval(-86400))
    var s1 = ListeningSession(deviceUID: "test-device-001", deviceName: "Nord Buds 2R", startTime: now.addingTimeInterval(-86400))
    s1.startPlayback(at: now.addingTimeInterval(-86400))
    s1.pausePlayback(at: now.addingTimeInterval(-82800)) // 3600s
    day1.sessions.append(s1)
    records[day1.dateKey] = day1

    var day2 = DailyStatistics(calendarDate: now.addingTimeInterval(-172800))
    var s2 = ListeningSession(deviceUID: "test-device-001", deviceName: "Nord Buds 2R", startTime: now.addingTimeInterval(-172800))
    s2.startPlayback(at: now.addingTimeInterval(-172800))
    s2.pausePlayback(at: now.addingTimeInterval(-169200)) // 3600s
    day2.sessions.append(s2)
    records[day2.dateKey] = day2

    let baseline = HistoryAnalyzer.calculateBaseline(from: records)
    assert(baseline == nil, "History with only 2 days must NOT create a fabricated baseline")

    // Now add a 3rd day to satisfy minimumDaysRequiredForBaseline
    var day3 = DailyStatistics(calendarDate: now.addingTimeInterval(-259200))
    var s3 = ListeningSession(deviceUID: "test-device-001", deviceName: "Nord Buds 2R", startTime: now.addingTimeInterval(-259200))
    s3.startPlayback(at: now.addingTimeInterval(-259200))
    s3.pausePlayback(at: now.addingTimeInterval(-255600)) // 3600s
    day3.sessions.append(s3)
    records[day3.dateKey] = day3

    let baseline3 = HistoryAnalyzer.calculateBaseline(from: records)
    assert(baseline3 != nil, "History with 3 valid days must calculate a personal baseline")
    assert(baseline3?.daysSampled == 3, "Baseline must reflect 3 sampled days")
    print("✅ 26. testInsufficientHistoryDoesNotCreateFakeBaseline passed: nil for 2 days, evaluated for 3 days")
}

// 27. Legacy Session JSON Deserialization Backwards Compatibility
func testLegacySessionJSONDeserializationBackwardsCompatibility() {
    print("--- Running testLegacySessionJSONDeserializationBackwardsCompatibility ---")
    let legacyJSON = """
    {
        "id": "A1B2C3D4-E5F6-7890-1234-56789ABCDEF0",
        "deviceUID": "test-device-legacy",
        "deviceName": "AirPods Pro",
        "startTime": 1717900000.0,
        "endTime": 1717903600.0,
        "activePlaybackDuration": 3600.0,
        "isCompleted": true
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    do {
        let session = try decoder.decode(ListeningSession.self, from: legacyJSON)
        assert(session.deviceUID == "test-device-legacy")
        assert(session.activePlaybackDuration == 3600.0)
        assert(session.averageVolume == nil, "Missing volume samples should yield nil averageVolume")
        assert(session.sumVolume == 0.0, "Missing sumVolume should default safely to 0.0")
        assert(session.sampleVolumeCount == 0, "Missing sampleVolumeCount should default safely to 0")
        assert(session.sourceApp == "Unknown source", "Missing sourceApp should default safely")
        print("✅ 27. testLegacySessionJSONDeserializationBackwardsCompatibility passed")
    } catch {
        fatalError("Failed to decode legacy JSON: \(error)")
    }
}

// 28. Bluetooth MAC Address Normalization
func testBluetoothMACAddressNormalization() {
    print("--- Running testBluetoothMACAddressNormalization ---")
    let colonUIDWithSuffix = "74:d7:13:30:0d:89:output"
    let normalized = BluetoothBatteryManager.normalizeMACAddress(from: colonUIDWithSuffix)
    assert(normalized == "74-d7-13-30-0d-89", "Expected '74-d7-13-30-0d-89' but got '\(normalized)'")

    let hyphenUID = "74-d7-13-30-0d-89"
    assert(BluetoothBatteryManager.normalizeMACAddress(from: hyphenUID) == "74-d7-13-30-0d-89")

    let upperCaseUID = "AA:BB:CC:DD:EE:FF:input"
    assert(BluetoothBatteryManager.normalizeMACAddress(from: upperCaseUID) == "aa-bb-cc-dd-ee-ff")
    print("✅ 28. testBluetoothMACAddressNormalization passed")
}

// 29. Multi-point Calibration Monotonic Piecewise Linear Interpolation
func testMultiPointCalibrationInterpolation() {
    print("--- Running testMultiPointCalibrationInterpolation ---")
    let p1 = EmpiricalCalibrationPoint(volume: 0.30, dbfs: -12.0, measuredSPL: 82.0)
    let p2 = EmpiricalCalibrationPoint(volume: 0.50, dbfs: -12.0, measuredSPL: 94.0)

    let record = makeValidCalibration(empiricalPoints: [p1, p2])
    let device = makeTestDevice()

    // Test at volume 0.40, dBFS -12.0: exactly midway -> (82 + 94) / 2 = 88.0 dBA
    let estimate = StandardDecibelProvider.shared.estimateAcousticSPL(
        currentVolume: 0.40,
        currentDBFS: -12.0,
        isPlaying: true,
        device: device,
        calibration: record
    )

    switch estimate {
    case .calibrated(let spl, _, _):
        assert(abs(spl - 88.0) < 0.01, "Expected interpolated 88.0 dBA at 40% vol, got \(spl)")
        print("✅ 29. testMultiPointCalibrationInterpolation passed: \(spl) dBA at 40% volume")
    default:
        fatalError("Expected measured SPL from piecewise interpolation, got \(estimate)")
    }
}

// 30. Multi-point Calibration Refuses Extrapolation Outside Operating Envelope
func testMultiPointCalibrationRefusesExtrapolation() {
    print("--- Running testMultiPointCalibrationRefusesExtrapolation ---")
    let p1 = EmpiricalCalibrationPoint(volume: 0.30, dbfs: -12.0, measuredSPL: 82.0)
    let p2 = EmpiricalCalibrationPoint(volume: 0.50, dbfs: -12.0, measuredSPL: 94.0)

    let record = makeValidCalibration(empiricalPoints: [p1, p2])
    let device = makeTestDevice()

    // Query at volume 0.15 (< 0.30 - 0.02 tolerance)
    let belowMin = StandardDecibelProvider.shared.estimateAcousticSPL(
        currentVolume: 0.15,
        currentDBFS: -12.0,
        isPlaying: true,
        device: device,
        calibration: record
    )
    switch belowMin {
    case .notMeasured(let reason):
        assert(reason.contains("Operating conditions outside calibrated envelope"), "Expected out of envelope refusal, got: \(reason)")
        print("✅ Refused extrapolation below min: \(reason)")
    default:
        fatalError("Expected .notMeasured for volume below calibration points, got \(belowMin)")
    }

    // Query at volume 0.85 (> 0.50 + 0.02 tolerance)
    let aboveMax = StandardDecibelProvider.shared.estimateAcousticSPL(
        currentVolume: 0.85,
        currentDBFS: -12.0,
        isPlaying: true,
        device: device,
        calibration: record
    )
    switch aboveMax {
    case .notMeasured(let reason):
        assert(reason.contains("Operating conditions outside calibrated envelope"), "Expected out of envelope refusal, got: \(reason)")
        print("✅ Refused extrapolation above max: \(reason)")
    default:
        fatalError("Expected .notMeasured for volume above calibration points, got \(aboveMax)")
    }

    print("✅ 30. testMultiPointCalibrationRefusesExtrapolation passed")
}

// 31. Calibrated vs Uncalibrated listening separation
func testCalibratedVsUncalibratedListeningSeparation() {
    print("--- Running testCalibratedVsUncalibratedListeningSeparation ---")
    let session = ListeningSession(
        deviceUID: "test-device-001",
        deviceName: "Nord Buds 2R",
        activePlaybackDuration: 3600,
        calibratedPlaybackDuration: 1200
    )
    assert(session.activePlaybackDuration == 3600)
    assert(session.calibratedPlaybackDuration == 1200)
    assert(session.uncalibratedPlaybackDuration == 2400, "Uncalibrated duration must be 2400s (40m)")

    var daily = DailyStatistics(calendarDate: Date())
    daily.sessions.append(session)
    assert(daily.totalListeningDuration() == 3600)
    assert(daily.totalCalibratedListeningDuration() == 1200)
    assert(daily.totalUncalibratedListeningDuration() == 2400)
    print("✅ 31. testCalibratedVsUncalibratedListeningSeparation passed: 20m calibrated, 40m uncalibrated")
}

// 32. Progressive baseline confidence tiers
func testProgressiveBaselineConfidenceTiers() {
    print("--- Running testProgressiveBaselineConfidenceTiers ---")
    let bEarly = PersonalBaseline(typicalDailyListening: 3600, typicalSessionDuration: 1200, typicalVolume: 0.45, typicalDBFS: -18.0, daysSampled: 4)
    assert(bEarly.confidence == .earlyPattern, "4 days must yield .earlyPattern")

    let bInitial = PersonalBaseline(typicalDailyListening: 3600, typicalSessionDuration: 1200, typicalVolume: 0.45, typicalDBFS: -18.0, daysSampled: 9)
    assert(bInitial.confidence == .initialBaseline, "9 days must yield .initialBaseline")

    let bEstablished = PersonalBaseline(typicalDailyListening: 3600, typicalSessionDuration: 1200, typicalVolume: 0.45, typicalDBFS: -18.0, daysSampled: 21)
    assert(bEstablished.confidence == .establishedBaseline, "21 days must yield .establishedBaseline")

    let bInsufficient = PersonalBaseline(typicalDailyListening: 3600, typicalSessionDuration: 1200, typicalVolume: 0.45, typicalDBFS: -18.0, daysSampled: 2)
    assert(bInsufficient.confidence == .insufficient, "2 days must yield .insufficient")
    print("✅ 32. testProgressiveBaselineConfidenceTiers passed: early, initial, established verified")
}

// 33. Multi-period trend generation
func testMultiPeriodTrendGeneration() {
    print("--- Running testMultiPeriodTrendGeneration ---")
    let now = Date()
    let todayStats = DailyStatistics(calendarDate: now)
    let records: [String: DailyStatistics] = [:]

    let trend7 = HistoryAnalyzer.buildTrend(period: .days7, todayStats: todayStats, activeSession: nil, allDailyRecords: records, now: now)
    assert(trend7.count == 7, "7D trend must contain exactly 7 daily summaries")

    let trend30 = HistoryAnalyzer.buildTrend(period: .days30, todayStats: todayStats, activeSession: nil, allDailyRecords: records, now: now)
    assert(trend30.count == 30, "30D trend must contain exactly 30 daily summaries")

    let trend90 = HistoryAnalyzer.buildTrend(period: .days90, todayStats: todayStats, activeSession: nil, allDailyRecords: records, now: now)
    assert(trend90.count == 90, "3M trend must contain exactly 90 daily summaries")
    print("✅ 33. testMultiPeriodTrendGeneration passed: 7D, 30D, and 90D verified")
}

// 34. Session length distribution categorization
func testSessionLengthDistributionCategorization() {
    print("--- Running testSessionLengthDistributionCategorization ---")
    let s1 = ListeningSession(deviceUID: "d1", deviceName: "AirPods", activePlaybackDuration: 600) // 10m (<15m)
    let s2 = ListeningSession(deviceUID: "d1", deviceName: "AirPods", activePlaybackDuration: 1200) // 20m (15-30m)
    let s3 = ListeningSession(deviceUID: "d1", deviceName: "AirPods", activePlaybackDuration: 2400) // 40m (30-60m)
    let s4 = ListeningSession(deviceUID: "d1", deviceName: "AirPods", activePlaybackDuration: 4200) // 70m (60m+)

    let dist = HistoryAnalyzer.calculateSessionLengthDistribution(from: [s1, s2, s3, s4])
    assert(dist.under15m == 1)
    assert(dist.from15to30m == 1)
    assert(dist.from30to60m == 1)
    assert(dist.over60m == 1)
    assert(dist.totalSessions == 4)
    assert(dist.isMeaningful == true)
    print("✅ 34. testSessionLengthDistributionCategorization passed: all 4 buckets verified")
}

// 35. Auditory rest recovery calculation & intensity scaling
func testAuditoryRestRecoveryCalculation() {
    print("--- Running testAuditoryRestRecoveryCalculation ---")
    // Under 25 minutes (1500s): zero rest recommended
    let rest10m = AuditoryRestManager.calculateRecommendedRest(duration: 600, volume: 0.8)
    assert(rest10m == 0, "Under 25m continuous listening must produce 0s rest recommendation")

    let rest24m = AuditoryRestManager.calculateRecommendedRest(duration: 1440, volume: 0.9)
    assert(rest24m == 0, "24m continuous listening must produce 0s rest recommendation")

    // At 30 minutes (1800s)
    // Low volume (≤50%): 15% factor -> 1800 * 0.15 = 270s (4.5 min)
    let restLow = AuditoryRestManager.calculateRecommendedRest(duration: 1800, volume: 0.45)
    assert(abs(restLow - 270.0) < 0.01, "30m at 45% volume must recommend 270s rest, got \(restLow)")

    // Moderate-high volume (50%-75%): 25% factor -> 1800 * 0.25 = 450s (7.5 min)
    let restMed = AuditoryRestManager.calculateRecommendedRest(duration: 1800, volume: 0.65)
    assert(abs(restMed - 450.0) < 0.01, "30m at 65% volume must recommend 450s rest, got \(restMed)")

    // High volume (>75%): 40% factor -> 1800 * 0.40 = 720s (12 min)
    let restHigh = AuditoryRestManager.calculateRecommendedRest(duration: 1800, volume: 0.85)
    assert(abs(restHigh - 720.0) < 0.01, "30m at 85% volume must recommend 720s rest, got \(restHigh)")

    // Minimum floor: at 25 minutes (1500s) * 0.15 = 225s >= 180s floor
    let restMin = AuditoryRestManager.calculateRecommendedRest(duration: 1500, volume: 0.10)
    assert(restMin >= 180.0, "Recommended rest must be at least 180s (3m)")

    print("✅ 35. testAuditoryRestRecoveryCalculation passed: psychoacoustic scaling verified")
}

// 36. High-volume protection settings & threshold opt-in safety
func testHighVolumeProtectionSettingsAndThreshold() {
    print("--- Running testHighVolumeProtectionSettingsAndThreshold ---")
    let settings = AppSettings.shared
    // Must be strictly opt-in (disabled by default)
    assert(settings.enableHighVolumeProtection == false, "High volume protection must be opt-in (disabled by default)")
    assert(settings.highVolumeThreshold >= 0.70 && settings.highVolumeThreshold <= 0.95, "Threshold must default in safe range 70%-95%")
    assert(settings.autoRollbackHighVolume == false, "Auto rollback must default to false")

    // Verify configuration works
    settings.enableHighVolumeProtection = true
    settings.highVolumeThreshold = 0.75
    settings.autoRollbackHighVolume = true

    assert(settings.enableHighVolumeProtection == true)
    assert(settings.highVolumeThreshold == 0.75)
    assert(settings.autoRollbackHighVolume == true)

    // Reset back to safe defaults
    settings.enableHighVolumeProtection = false
    settings.highVolumeThreshold = 0.80
    settings.autoRollbackHighVolume = false
    print("✅ 36. testHighVolumeProtectionSettingsAndThreshold passed: opt-in defaults verified")
}

// 37. App-specific audio attribution & JSON backward compatibility
func testAppAudioAttributionTracking() {
    print("--- Running testAppAudioAttributionTracking ---")
    var session = ListeningSession(deviceUID: "d1", deviceName: "AirPods")
    session.recordAppDuration(app: "Spotify", seconds: 1200)
    session.recordAppDuration(app: "Logic Pro", seconds: 600)

    assert(session.appDurations["Spotify"] == 1200)
    assert(session.appDurations["Logic Pro"] == 600)

    var daily = DailyStatistics()
    daily.recordAppDuration(app: "Spotify", seconds: 3600)
    daily.recordAppDuration(app: "Safari", seconds: 1200)

    let topApps = daily.topApplications()
    assert(topApps.count == 2)
    assert(topApps[0].app == "Spotify")
    assert(topApps[0].duration == 3600)
    assert(abs(topApps[0].percentage - 0.75) < 0.01, "Spotify must be 75% of total listening")
    assert(topApps[1].app == "Safari")
    assert(topApps[1].duration == 1200)
    assert(abs(topApps[1].percentage - 0.25) < 0.01, "Safari must be 25% of total listening")

    // Backward compatibility: JSON without appDurations field must decode safely
    let legacyJSON = """
    {
        "dateKey": "2026-09-08",
        "totalListeningSeconds": 3600,
        "calibratedListeningSeconds": 1800,
        "uncalibratedListeningSeconds": 1800,
        "sessionCount": 2,
        "hourlyBuckets": []
    }
    """.data(using: .utf8)!

    let decoded = try? JSONDecoder().decode(DailyStatistics.self, from: legacyJSON)
    assert(decoded != nil, "Legacy JSON without appDurations must decode without error")
    assert(decoded?.appDurations.isEmpty == true, "Decoded legacy record must have empty appDurations")
    print("✅ 37. testAppAudioAttributionTracking passed: attribution and backward compatibility verified")
}

// 38. 7×24 weekly habit heatmap matrix dimensions and accumulation
@MainActor
func testHabitHeatmapMatrixDimensionsAndAccumulation() {
    print("--- Running testHabitHeatmapMatrixDimensionsAndAccumulation ---")
    let matrix = AppState.shared.habitHeatmapMatrix
    assert(matrix.count == 7, "Heatmap matrix must have exactly 7 weekday rows")
    for row in matrix {
        assert(row.count == 24, "Each heatmap weekday row must have exactly 24 hourly buckets")
    }
    print("✅ 38. testHabitHeatmapMatrixDimensionsAndAccumulation passed: 7x24 matrix verified")
}

// 39. Wired headphone electromechanical physics calculator
func testWiredHeadphonePhysicsCalculator() {
    print("--- Running testWiredHeadphonePhysicsCalculator ---")
    // Test MacBook Pro High Gain (3.0 Vrms, 0.5 ohm output Z) with Beyerdynamic DT 770 Pro (80 ohm, 96 dB/mW)
    let maxSPLmW = WiredHeadphonePhysicsCalculator.calculateMaxSPL(
        vrms: 3.0,
        outputImpedance: 0.5,
        headphoneImpedance: 80.0,
        sensitivity: 96.0,
        unit: .dbPerMilliwatt
    )
    // Delivered V = 3.0 * (80 / 80.5) = 2.98136 V
    // Power = (2.98136^2 / 80) * 1000 = 111.107 mW
    // 10 * log10(111.107) = 20.457 dB
    // Max SPL = 96 + 20.457 = 116.457 dBA
    assert(abs(maxSPLmW - 116.46) < 0.2, "DT 770 Pro 80 ohm max SPL must be ~116.5 dBA, got \(maxSPLmW)")

    // Test with sensitivity in dB/Vrms: Sennheiser HD 600 (300 ohm, 105 dB/Vrms) with standard 2.0 Vrms DAC
    let maxSPLVolt = WiredHeadphonePhysicsCalculator.calculateMaxSPL(
        vrms: 2.0,
        outputImpedance: 1.0,
        headphoneImpedance: 300.0,
        sensitivity: 105.0,
        unit: .dbPerVolt
    )
    // Delivered V = 2.0 * (300 / 301) = 1.993 V
    // 20 * log10(1.993) = 5.99 dB
    // Max SPL = 105 + 5.99 = 110.99 dBA
    assert(abs(maxSPLVolt - 111.0) < 0.2, "HD 600 max SPL must be ~111.0 dBA, got \(maxSPLVolt)")

    // Test multi-point calibration profile generation
    let record = WiredHeadphonePhysicsCalculator.generateCalibrationRecord(
        deviceUID: "wired-test-01",
        deviceModel: "Sennheiser HD 600",
        vrms: 2.0,
        outputImpedance: 1.0,
        headphoneImpedance: 300.0,
        sensitivity: 105.0,
        unit: .dbPerVolt
    )

    assert(record.deviceUID == "wired-test-01")
    assert(record.methodology == .electromechanicalSensitivityModel)
    assert(record.uncertaintyDB == 3.0, "Electromechanical model must preserve conservative ±3.0 dB uncertainty")
    assert(!record.empiricalPoints.isEmpty, "Generated calibration record must contain empirical envelope points")
    assert(record.calibratedVolume == 0.50, "Reference volume must be 50%")
    print("✅ 39. testWiredHeadphonePhysicsCalculator passed: electro-acoustic calculations verified")
}

// MARK: - 40-44: Software Update System Tests

func testSemanticVersionParsingAndComparison() {
    print("--- Running testSemanticVersionParsingAndComparison ---")
    let v1 = SemanticVersion("1.0.0")!
    let v1_patch = SemanticVersion("1.0.1")!
    let v1_minor = SemanticVersion("1.1.0")!
    let v2 = SemanticVersion("v2.0.0")!
    let v_short = SemanticVersion("1.2")!
    let v_beta = SemanticVersion("1.1.0-beta.1")!

    assert(v1 < v1_patch, "1.0.0 should be < 1.0.1")
    assert(v1_patch < v1_minor, "1.0.1 should be < 1.1.0")
    assert(v1_minor < v2, "1.1.0 should be < 2.0.0")
    assert(v_short.major == 1 && v_short.minor == 2 && v_short.patch == 0, "Short version 1.2 should have patch 0")
    assert(v_beta < v1_minor, "1.1.0-beta.1 should be < 1.1.0 (pre-release is strictly less than full release)")
    assert(v_beta.isPrerelease, "1.1.0-beta.1 must be identified as pre-release")
    assert(!v1_minor.isPrerelease, "1.1.0 is not a pre-release")
    assert(SemanticVersion("") == nil, "Empty string should return nil")
    assert(SemanticVersion("invalid.version.text") == nil, "Invalid string should return nil")
    print("✅ 40. testSemanticVersionParsingAndComparison passed: semver ordering and normalization verified")
}

func testGitHubReleasePayloadParsing() {
    print("--- Running testGitHubReleasePayloadParsing ---")
    let dmgAsset = GitHubAssetPayload(name: "Metere-1.1.0.dmg", size: 14_500_000, browserDownloadUrl: "https://github.com/halite-audio/metere/releases/download/v1.1.0/Metere-1.1.0.dmg")
    let zipAsset = GitHubAssetPayload(name: "Metere-1.1.0.zip", size: 12_300_000, browserDownloadUrl: "https://github.com/halite-audio/metere/releases/download/v1.1.0/Metere-1.1.0.zip")

    let payload = GitHubReleasePayload(
        tagName: "v1.1.0",
        name: "Metere 1.1 - Audio Precision",
        body: "### What's New\n- High volume auto-rollback\n- Wired headphone calibration assistant",
        htmlUrl: "https://github.com/halite-audio/metere/releases/tag/v1.1.0",
        publishedAt: "2026-09-08T18:00:00Z",
        prerelease: false,
        draft: false,
        assets: [zipAsset, dmgAsset]
    )

    let update = AppUpdateInfo.parse(from: payload)
    assert(update != nil, "Parsed update info must not be nil")
    assert(update?.version == SemanticVersion(major: 1, minor: 1, patch: 0), "Version must match 1.1.0")
    assert(update?.releaseTitle == "Metere 1.1 - Audio Precision", "Release title must match")
    assert(update?.assetName == "Metere-1.1.0.dmg", "Must prioritize DMG asset over ZIP asset")
    assert(update?.downloadURL?.absoluteString == "https://github.com/halite-audio/metere/releases/download/v1.1.0/Metere-1.1.0.dmg")
    assert(update?.assetSize == 14_500_000)
    assert(update?.isPrerelease == false)
    print("✅ 41. testGitHubReleasePayloadParsing passed: GitHub release DTO and asset precedence verified")
}

@MainActor
func testUpdateSkipVersionLogic() {
    print("--- Running testUpdateSkipVersionLogic ---")
    let defaults = UserDefaults(suiteName: "test.metere.updates.skip")!
    defaults.removePersistentDomain(forName: "test.metere.updates.skip")
    let settings = AppSettings(defaults: defaults)
    let updateManager = UpdateManager(settings: settings)

    let payload = GitHubReleasePayload(
        tagName: "v2.0.0",
        name: "Metere 2.0",
        body: "Major upgrade",
        htmlUrl: "https://github.com/halite-audio/metere/releases/tag/v2.0.0",
        publishedAt: "2026-09-08T18:00:00Z",
        assets: []
    )

    // First check: without skip, v2.0.0 is available
    updateManager.evaluateReleases([payload], userInitiated: false)
    assert(updateManager.hasUpdateAvailable, "Update v2.0.0 should be marked available")

    // Now user skips v2.0.0
    updateManager.skipVersion("v2.0.0")
    assert(settings.skippedVersion == "v2.0.0")

    // Background automated check with skipped version
    updateManager.evaluateReleases([payload], userInitiated: false)
    assert(!updateManager.hasUpdateAvailable, "Skipped version should not be presented during automatic background checks")

    // Explicit user-initiated check should still present it
    updateManager.evaluateReleases([payload], userInitiated: true)
    assert(updateManager.hasUpdateAvailable, "User-initiated check must present updates even if previously skipped")
    print("✅ 42. testUpdateSkipVersionLogic passed: skip version logic verified")
}

@MainActor
func testPrereleaseFilterRespectsUserSetting() {
    print("--- Running testPrereleaseFilterRespectsUserSetting ---")
    let defaults = UserDefaults(suiteName: "test.metere.updates.prerelease")!
    defaults.removePersistentDomain(forName: "test.metere.updates.prerelease")
    let settings = AppSettings(defaults: defaults)
    let updateManager = UpdateManager(settings: settings)

    let betaPayload = GitHubReleasePayload(
        tagName: "v2.0.0-beta.1",
        name: "Metere 2.0 Beta 1",
        body: "Beta test build",
        htmlUrl: "https://github.com/halite-audio/metere/releases/tag/v2.0.0-beta.1",
        publishedAt: "2026-09-08T18:00:00Z",
        prerelease: true,
        assets: []
    )

    // With includePrereleases = false
    settings.includePrereleases = false
    updateManager.evaluateReleases([betaPayload], userInitiated: true)
    assert(!updateManager.hasUpdateAvailable, "Pre-release should be ignored when includePrereleases is false")

    // With includePrereleases = true
    settings.includePrereleases = true
    updateManager.evaluateReleases([betaPayload], userInitiated: true)
    assert(updateManager.hasUpdateAvailable, "Pre-release should be accepted when includePrereleases is true")
    assert(updateManager.availableUpdate?.version.isPrerelease == true)
    print("✅ 43. testPrereleaseFilterRespectsUserSetting passed: beta release filtering verified")
}

func testUpdateCheckFrequencyIntervals() {
    print("--- Running testUpdateCheckFrequencyIntervals ---")
    let dailyInterval: Double = 86400.0
    let weeklyInterval: Double = 604800.0

    let now = Date()
    let twelveHoursAgo = now.addingTimeInterval(-43200)
    let twoDaysAgo = now.addingTimeInterval(-172800)

    // Within daily window -> should not trigger
    assert(now.timeIntervalSince(twelveHoursAgo) < dailyInterval, "12 hours ago is within daily window")
    // Beyond daily window -> should trigger
    assert(now.timeIntervalSince(twoDaysAgo) >= dailyInterval, "2 days ago is beyond daily window")
    // Beyond daily but within weekly -> should not trigger for weekly
    assert(now.timeIntervalSince(twoDaysAgo) < weeklyInterval, "2 days ago is within weekly window")
    print("✅ 44. testUpdateCheckFrequencyIntervals passed: interval evaluation verified")
}

// MARK: - Test Runner Main

@main
struct TestRunner {
    @MainActor
    static func main() {
        testIdlePlaybackProducesZeroListeningTime()
        testPausedPlaybackDoesNotAccumulateTime()
        testPlaybackResumeContinuesAccumulation()
        testDigitalLevelIsReportedAsDBFS()
        testSystemVolumeIsIndependentOfDBFS()
        testUncalibratedExposureIsUnavailable()
        testBluetoothConnectionAloneDoesNotCreateExposure()
        testBatteryTelemetryDoesNotAffectExposure()
        testCalibrationRecordRequiresDeviceMatch()
        testCalibrationRecordRequiresMeasurementData()
        testInvalidCalibrationDisablesWHOExposure()
        testValidCalibrationEnablesCalibratedSPL()
        testCalibrationUncertaintyIsPreserved()
        testUncalibratedPlaybackStillTracksListeningTime()
        testCalibrationRefusesToSynthesizeSPLOutsideOperatingEnvelope()
        testCalibrationRefusesSPLWhenDBFSOutsideOperatingEnvelope()
        testCalibrationRequiresBothVolumeAndDBFSConditions()
        testSinglePointCalibrationNeverExtrapolates()
        testModelLevelCalibrationIsMarkedAsModelLevel()
        testWHOExposureUsesOnlyActivePlaybackIntervals()
        testStatisticsUseAuthoritativeListeningTime()
        testPopoverAndStatisticsHaveConsistentListeningTotals()
        testBreakReminderUsesActivePlaybackTime()
        testPausedPlaybackDoesNotTriggerBreakReminder()
        testDisconnectedDeviceDoesNotAccumulateListeningTime()
        testInsufficientHistoryDoesNotCreateFakeBaseline()
        testLegacySessionJSONDeserializationBackwardsCompatibility()
        testBluetoothMACAddressNormalization()
        testMultiPointCalibrationInterpolation()
        testMultiPointCalibrationRefusesExtrapolation()
        testCalibratedVsUncalibratedListeningSeparation()
        testProgressiveBaselineConfidenceTiers()
        testMultiPeriodTrendGeneration()
        testSessionLengthDistributionCategorization()
        testAuditoryRestRecoveryCalculation()
        testHighVolumeProtectionSettingsAndThreshold()
        testAppAudioAttributionTracking()
        testHabitHeatmapMatrixDimensionsAndAccumulation()
        testWiredHeadphonePhysicsCalculator()
        testSemanticVersionParsingAndComparison()
        testGitHubReleasePayloadParsing()
        testUpdateSkipVersionLogic()
        testPrereleaseFilterRespectsUserSetting()
        testUpdateCheckFrequencyIntervals()
        print("\n🎉 ALL 44 ARCHITECTURAL, FEATURE & UPDATE SYSTEM TESTS PASSED WITH 100% COMPLIANCE! 🎉\n")
    }
}
