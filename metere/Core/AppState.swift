//
//  AppState.swift
//  metere
//

import Foundation
import SwiftUI
import Combine
import UserNotifications

@MainActor
public final class AppState: ObservableObject, BluetoothDeviceManagerDelegate {
    public static let shared = AppState()

    public let settings: AppSettings
    public let deviceManager: BluetoothDeviceManager
    public let sessionManager: ListeningSessionManager
    public let decibelProvider: DecibelProvider
    public let batteryManager: BluetoothBatteryManager
    public let updateManager: UpdateManager

    @Published public private(set) var activeHeadphone: AudioDevice?
    @Published public private(set) var currentDefaultDevice: AudioDevice?
    @Published public private(set) var isAudioPlaying: Bool = false
    @Published public private(set) var currentVolumeScalar: Float = 0.0
    @Published public private(set) var batteryInfo: DeviceBatteryInfo?

    // Calibration Record (nil by default, requiring empirical acoustic calibration)
    @Published public var activeCalibrationRecord: AcousticCalibrationRecord?

    // Today's aggregated metrics
    @Published public private(set) var todayListeningDuration: TimeInterval = 0
    @Published public private(set) var todayAverageDBFS: Double? = nil
    @Published public private(set) var todaySessionCount: Int = 0
    @Published public private(set) var hourlyBuckets: [HourlyExposure] = []
    @Published public private(set) var activeSessionDuration: TimeInterval = 0

    private var uiUpdateTimer: Timer?
    private var batteryTimer: Timer?
    private var settingsCancellable: AnyCancellable?

    public init(
        settings: AppSettings = .shared,
        deviceManager: BluetoothDeviceManager = BluetoothDeviceManager(),
        sessionManager: ListeningSessionManager = .shared,
        decibelProvider: DecibelProvider = StandardDecibelProvider.shared,
        batteryManager: BluetoothBatteryManager = .shared,
        updateManager: UpdateManager = .shared
    ) {
        self.settings = settings
        self.deviceManager = deviceManager
        self.sessionManager = sessionManager
        self.decibelProvider = decibelProvider
        self.batteryManager = batteryManager
        self.updateManager = updateManager

        self.deviceManager.delegate = self

        // Forward settings changes directly to UI and request notification authorization when features are enabled
        self.settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.settings.breakReminderInterval > 0 || self.settings.notifyOnRouteChange {
                    self.requestNotificationAuthorization()
                }
                self.objectWillChange.send()
                self.refreshMetrics()
            }
        }

        // Wire up session updates
        self.sessionManager.onStatisticsUpdated = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshMetrics()
            }
        }

        self.sessionManager.calibrationRecordProvider = { [weak self] in
            self?.activeCalibrationRecord
        }

        // Start managers
        self.deviceManager.start()
        startTimers()
        refreshMetrics()
        refreshBattery()
        self.updateManager.startScheduledChecks()

        if settings.breakReminderInterval > 0 || settings.notifyOnRouteChange {
            requestNotificationAuthorization()
        }
    }

    public func requestNotificationAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[AppState] Notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        uiUpdateTimer?.invalidate()
        batteryTimer?.invalidate()
    }

    private func startTimers() {
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMetrics()
            }
        }

        batteryTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshBattery()
            }
        }
    }

    public func refreshBattery() {
        if let headphone = activeHeadphone {
            self.batteryInfo = batteryManager.getBatteryInfo(for: headphone)
        } else {
            self.batteryInfo = nil
        }
    }

    public func refreshMetrics() {
        let now = Date()
        let active = sessionManager.activeSession
        let today = sessionManager.todayStatistics

        self.todayListeningDuration = today.totalListeningDuration(activeSession: active, now: now)
        self.todayAverageDBFS = today.averageDBFS(activeSession: active)
        self.todaySessionCount = today.totalSessionCount(activeSession: active)
        self.hourlyBuckets = today.hourlyBuckets

        if let active = active, active.isActive {
            self.activeSessionDuration = active.duration(at: now)
        } else {
            self.activeSessionDuration = 0
        }
    }

    // MARK: - BluetoothDeviceManagerDelegate

    public func activeHeadphoneDidChange(to device: AudioDevice?) {
        let previous = self.activeHeadphone
        self.activeHeadphone = device
        BluetoothDeviceManagerDelegateProxy.shared.currentActiveHeadphone = device

        if let device = device {
            let vol = CoreAudioBridge.shared.getVolume(for: device.id)
            self.currentVolumeScalar = vol
            let isPlaying = CoreAudioBridge.shared.isAudioActivelyPlaying(for: device.id)
            self.isAudioPlaying = isPlaying
            sessionManager.handleHeadphoneConnected(device: device, isPlaying: isPlaying)
            refreshBattery()
            if previous?.uid != device.uid {
                postRouteChangeNotification(to: device.name)
            }
        } else {
            self.isAudioPlaying = false
            self.batteryInfo = nil
            sessionManager.handleHeadphoneDisconnected()
            if let prev = previous {
                postRouteChangeNotification(to: currentDefaultDevice?.name ?? "Default Output")
            }
        }
        refreshMetrics()
    }

    public func defaultOutputDeviceDidChange(to device: AudioDevice?) {
        self.currentDefaultDevice = device
    }

    private func postRouteChangeNotification(to deviceName: String) {
        guard settings.notifyOnRouteChange else { return }
        let content = UNMutableNotificationContent()
        content.title = "Audio Output Changed"
        content.body = "Output route is now: \(deviceName)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private var lastHighVolumeAlertDate: Date?

    public func deviceVolumeDidChange(volume: Float) {
        self.currentVolumeScalar = volume
        if settings.enableHighVolumeProtection && volume >= settings.highVolumeThreshold {
            handleHighVolumeExceeded(volume: volume)
        }
        refreshMetrics()
    }

    private func handleHighVolumeExceeded(volume: Float) {
        let now = Date()
        if let last = lastHighVolumeAlertDate, now.timeIntervalSince(last) < 60 {
            return
        }
        lastHighVolumeAlertDate = now

        let percent = Int(round(volume * 100))
        let thresholdPercent = Int(round(settings.highVolumeThreshold * 100))

        let content = UNMutableNotificationContent()
        content.title = "High Volume Protection"
        content.body = "System volume was increased to \(percent)%. Prolonged listening above \(thresholdPercent)% accelerates ear fatigue."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "metere.highVolumeProtection.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)

        if settings.autoRollbackHighVolume, let dev = activeHeadphone {
            let rollbackVol = min(volume, max(0.10, settings.highVolumeThreshold - 0.05))
            CoreAudioBridge.shared.setVolume(rollbackVol, for: dev.id)
            self.currentVolumeScalar = rollbackVol
        }
    }

    public func audioPlaybackStateDidChange(isPlaying: Bool) {
        self.isAudioPlaying = isPlaying
        sessionManager.handlePlaybackStateChanged(isPlaying: isPlaying)
        refreshMetrics()
    }

    // MARK: - Honest Presentation & Calibration Properties

    public var isHeadphoneConnected: Bool {
        activeHeadphone != nil
    }

    public var systemVolumePercentage: Int {
        Int(round(currentVolumeScalar * 100))
    }

    public var formattedSystemVolume: String {
        "\(systemVolumePercentage)%"
    }

    /// Measurable digital attenuation in dBFS. Returns nil when playback is idle/paused.
    public var digitalLevelDBFS: Double? {
        guard isHeadphoneConnected, isAudioPlaying else { return nil }
        return decibelProvider.digitalAttenuationDBFS(volumeScalar: currentVolumeScalar)
    }

    /// Formatted digital level display. Explicitly outputs "Idle" or "Disconnected" when no audio is playing.
    public var formattedDigitalLevel: String {
        guard isHeadphoneConnected else { return "Disconnected" }
        guard isAudioPlaying else { return "Idle" }
        if let dbfs = digitalLevelDBFS {
            return String(format: "%.1f dBFS", dbfs)
        }
        return "Muted"
    }

    /// Acoustic SPL Status evaluated against strict calibration and operating envelope
    public var acousticSPLStatus: AcousticSPLStatus {
        decibelProvider.estimateAcousticSPL(
            currentVolume: currentVolumeScalar,
            currentDBFS: digitalLevelDBFS,
            isPlaying: isAudioPlaying,
            device: activeHeadphone,
            calibration: activeCalibrationRecord
        )
    }

    /// WHO Exposure Dose Status evaluated strictly from calibrated SPL and active playback duration
    public var whoExposureStatus: WHOExposureStatus {
        decibelProvider.evaluateWHOExposure(
            splStatus: acousticSPLStatus,
            activeListeningSeconds: todayListeningDuration
        )
    }

    public var formattedPlaybackState: String {
        guard isHeadphoneConnected else { return "Disconnected" }
        return isAudioPlaying ? "Active" : "Paused / Idle"
    }

    /// Header connection and playback status string (e.g. "Connected · Playing", "Connected · Paused")
    public var headerPlaybackStatusText: String {
        guard isHeadphoneConnected else { return "Disconnected" }
        if isAudioPlaying {
            return "Connected · Playing"
        } else if activeSessionDuration > 0 {
            return "Connected · Paused"
        } else {
            return "Connected · No Audio"
        }
    }

    public var isPlayingOrActive: Bool {
        isHeadphoneConnected && isAudioPlaying
    }

    public var formattedTodayDuration: String {
        DailyStatistics.formattedDuration(todayListeningDuration)
    }

    public var formattedSessionDuration: String {
        DailyStatistics.formattedDuration(activeSessionDuration)
    }

    /// Current active session display: e.g. "24m", "Paused", or "—"
    public var formattedCurrentSession: String {
        guard isHeadphoneConnected else { return "—" }
        if isAudioPlaying {
            return DailyStatistics.formattedDuration(activeSessionDuration)
        } else if activeSessionDuration > 0 {
            return "Paused"
        } else {
            return "—"
        }
    }

    public var continuousListeningDuration: TimeInterval {
        sessionManager.continuousPlaybackDuration
    }

    // MARK: - Dedicated Statistics & Insights Accessors

    public var calibratedTodayDuration: TimeInterval {
        sessionManager.todayStatistics.totalCalibratedListeningDuration(activeSession: sessionManager.activeSession)
    }

    public var uncalibratedTodayDuration: TimeInterval {
        sessionManager.todayStatistics.totalUncalibratedListeningDuration(activeSession: sessionManager.activeSession, now: Date())
    }

    public var formattedCalibratedTodayDuration: String {
        DailyStatistics.formattedDuration(calibratedTodayDuration)
    }

    public var formattedUncalibratedTodayDuration: String {
        DailyStatistics.formattedDuration(uncalibratedTodayDuration)
    }

    public var todayAverageSessionDuration: TimeInterval {
        let sessions = sessionManager.todayStatistics.sessions
        let active = sessionManager.activeSession
        var allDurations = sessions.map { $0.activePlaybackDuration }
        if let a = active, a.isActive {
            allDurations.append(a.duration())
        }
        guard !allDurations.isEmpty else { return 0 }
        return allDurations.reduce(0, +) / Double(allDurations.count)
    }

    public var formattedTodayAverageSession: String {
        DailyStatistics.formattedDuration(todayAverageSessionDuration)
    }

    public var todayLongestSessionDuration: TimeInterval {
        let sessions = sessionManager.todayStatistics.sessions
        let active = sessionManager.activeSession
        var maxDur: TimeInterval = 0
        for s in sessions {
            maxDur = max(maxDur, s.activePlaybackDuration)
        }
        if let a = active, a.isActive {
            maxDur = max(maxDur, a.duration())
        }
        return maxDur
    }

    public var formattedTodayLongestSession: String {
        DailyStatistics.formattedDuration(todayLongestSessionDuration)
    }

    public var personalBaseline: PersonalBaseline? {
        sessionManager.getPersonalBaseline()
    }

    public var listeningInsights: [ListeningInsight] {
        sessionManager.getInsights()
    }

    public var weeklyTrend: [DayTrendSummary] {
        sessionManager.getWeeklyTrend()
    }

    public func trend(for period: TrendPeriod) -> [DayTrendSummary] {
        sessionManager.getTrend(period: period)
    }

    public var activeDaysThisWeek: (active: Int, total: Int) {
        sessionManager.getActiveDaysPast7()
    }

    public var sessionsOver60mCount: Int {
        sessionManager.getSessionsOver60mThisWeek()
    }

    public var sessionLengthDistribution: SessionLengthDistribution {
        sessionManager.getSessionLengthDistribution()
    }

    public var historicalSessions: [ListeningSession] {
        sessionManager.getAllHistoricalSessions()
    }

    public var auditoryRestManager: AuditoryRestManager {
        AuditoryRestManager.shared
    }

    public var topApplications: [(app: String, duration: TimeInterval, percentage: Double)] {
        sessionManager.getTopApplications(limit: 5)
    }

    /// Generates a 7-day (Mon..Sun) by 24-hour (0..23) matrix of active listening seconds for the weekly habit heatmap
    public var habitHeatmapMatrix: [[Double]] {
        var matrix = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        let calendar = Calendar.current
        let now = Date()

        for dayOffset in 0..<7 {
            guard let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let key = DailyStatistics.makeDateKey(for: targetDate, calendar: calendar)

            // Weekday index: 0 = Mon, ..., 6 = Sun
            let weekday = calendar.component(.weekday, from: targetDate)
            let rowIndex = (weekday + 5) % 7 // Sunday (1) -> 6, Monday (2) -> 0, etc.

            let stats: DailyStatistics?
            if key == sessionManager.todayStatistics.dateKey {
                stats = sessionManager.todayStatistics
            } else {
                stats = sessionManager.allDailyRecords[key]
            }

            if let stats = stats {
                for bucket in stats.hourlyBuckets {
                    if bucket.hour >= 0 && bucket.hour < 24 {
                        matrix[rowIndex][bucket.hour] += bucket.listeningSeconds
                    }
                }
            }
        }
        return matrix
    }

    public var deviceSummaries: [DeviceUsageSummary] {
        sessionManager.getDeviceSummaries()
    }

    public var menuBarTitle: String {
        guard settings.showDecibelsInMenuBar else { return "" }
        guard isHeadphoneConnected else { return "—" }

        if isAudioPlaying {
            if let dbfs = digitalLevelDBFS {
                return String(format: "%.0f dBFS", dbfs)
            }
            return "Active"
        } else {
            return "Idle"
        }
    }

    public var menuBarSymbolName: String {
        if let headphone = activeHeadphone {
            return headphone.sfSymbolName
        }
        return "headphones"
    }
}
