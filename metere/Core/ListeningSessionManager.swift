//
//  ListeningSessionManager.swift
//  metere
//

import Foundation
import AppKit
import Combine
import UserNotifications

public struct DeviceUsageSummary: Identifiable, Equatable, Sendable {
    public var id: String { deviceUID }
    public let deviceUID: String
    public let deviceName: String
    public var totalListeningDuration: TimeInterval
    public var sessionCount: Int
    public var averageVolume: Float?

    public init(
        deviceUID: String,
        deviceName: String,
        totalListeningDuration: TimeInterval,
        sessionCount: Int,
        averageVolume: Float? = nil
    ) {
        self.deviceUID = deviceUID
        self.deviceName = deviceName
        self.totalListeningDuration = totalListeningDuration
        self.sessionCount = sessionCount
        self.averageVolume = averageVolume
    }

    public var formattedDuration: String {
        DailyStatistics.formattedDuration(totalListeningDuration)
    }

    public var formattedVolume: String {
        if let v = averageVolume {
            return "\(Int(round(v * 100)))%"
        }
        return "—"
    }
}

public final class ListeningSessionManager {
    public static let shared = ListeningSessionManager()

    private let persistence: PersistenceManager
    private let decibelProvider: DecibelProvider
    private let settings: AppSettings

    // State
    public private(set) var todayStatistics: DailyStatistics
    public private(set) var activeSession: ListeningSession?
    public private(set) var allDailyRecords: [String: DailyStatistics] = [:]
    public private(set) var isAudioPlaying: Bool = false

    // Break reminder tracking (strictly active playback duration)
    public private(set) var continuousPlaybackDuration: TimeInterval = 0
    public private(set) var currentContinuousPlaybackStart: Date?
    private var lastPauseTimestamp: Date?

    private var samplingTimer: Timer?
    private var midnightCheckTimer: Timer?
    private var lastSampleDate: Date?
    private var settingsCancellable: AnyCancellable?

    public var onStatisticsUpdated: (() -> Void)?
    public var calibrationRecordProvider: (() -> AcousticCalibrationRecord?)?

    public init(
        persistence: PersistenceManager = .shared,
        decibelProvider: DecibelProvider = StandardDecibelProvider.shared,
        settings: AppSettings = .shared
    ) {
        self.persistence = persistence
        self.decibelProvider = decibelProvider
        self.settings = settings
        self.todayStatistics = DailyStatistics()

        loadPersistedState()
        setupSystemNotificationObservers()
        startMidnightRolloverTimer()

        // Dynamically restart sampling timer if interval setting changes during active playback
        self.settingsCancellable = settings.$samplingInterval.dropFirst().sink { [weak self] _ in
            guard let self = self, self.isAudioPlaying else { return }
            self.startSamplingTimer()
        }
    }

    deinit {
        stopSamplingTimer()
        midnightCheckTimer?.invalidate()
    }

    // MARK: - Startup & Recovery

    private func loadPersistedState() {
        let saved = persistence.loadData()
        self.allDailyRecords = saved.dailyRecords

        let todayKey = DailyStatistics.makeDateKey(for: Date())
        if let existingToday = saved.dailyRecords[todayKey] {
            self.todayStatistics = existingToday
        } else {
            self.todayStatistics = DailyStatistics(calendarDate: Date())
        }

        // Crash/Shutdown Recovery:
        // Finalize unclosed active session from previous run to preserve active playback seconds
        if var recovered = saved.activeSession, recovered.isActive {
            let recoveryEnd = recovered.lastHeartbeat
            recovered.complete(at: recoveryEnd)
            let sessionDateKey = DailyStatistics.makeDateKey(for: recovered.startTime)
            if sessionDateKey == todayKey {
                self.todayStatistics.sessions.append(recovered)
            } else if var pastStats = self.allDailyRecords[sessionDateKey] {
                pastStats.sessions.append(recovered)
                self.allDailyRecords[sessionDateKey] = pastStats
            }
            self.activeSession = nil
            persistCurrentState(sync: false)
        }
    }

    private func setupSystemNotificationObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        let appCenter = NotificationCenter.default

        // Sleep
        wsCenter.addObserver(
            self,
            selector: #selector(handleSystemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        // Wake
        wsCenter.addObserver(
            self,
            selector: #selector(handleSystemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // App Will Terminate
        appCenter.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    // MARK: - Session Lifecycle Management

    public func handleHeadphoneConnected(device: AudioDevice, isPlaying: Bool = false) {
        checkMidnightRollover()

        if let existing = activeSession {
            if existing.deviceUID == device.uid {
                // Same device already active
                return
            } else {
                finalizeActiveSession(at: Date())
            }
        }

        let now = Date()
        var newSession = ListeningSession(
            deviceUID: device.uid,
            deviceName: device.name,
            startTime: now,
            lastHeartbeat: now
        )

        if isPlaying {
            newSession.startPlayback(at: now)
            self.isAudioPlaying = true
            if let lastPause = lastPauseTimestamp, now.timeIntervalSince(lastPause) > 300 {
                continuousPlaybackDuration = 0
            }
            if currentContinuousPlaybackStart == nil {
                currentContinuousPlaybackStart = now
            }
            startSamplingTimer()
        } else {
            self.isAudioPlaying = false
            stopSamplingTimer()
        }

        self.activeSession = newSession
        persistCurrentState(sync: false)
        onStatisticsUpdated?()
    }

    public func handlePlaybackStateChanged(isPlaying: Bool) {
        guard var session = activeSession else { return }
        checkMidnightRollover()

        let now = Date()
        self.isAudioPlaying = isPlaying

        if isPlaying {
            session.startPlayback(at: now)
            self.activeSession = session
            if let lastPause = lastPauseTimestamp, now.timeIntervalSince(lastPause) > 300 {
                continuousPlaybackDuration = 0
            }
            if currentContinuousPlaybackStart == nil {
                currentContinuousPlaybackStart = now
            }
            DispatchQueue.main.async {
                AuditoryRestManager.shared.handlePlaybackResumed()
            }
            startSamplingTimer()
        } else {
            session.pausePlayback(at: now)
            self.activeSession = session
            if let start = currentContinuousPlaybackStart {
                continuousPlaybackDuration += max(0, now.timeIntervalSince(start))
                currentContinuousPlaybackStart = nil
            }
            let avgVol = session.averageVolume ?? 0.50
            let duration = continuousPlaybackDuration
            DispatchQueue.main.async {
                AuditoryRestManager.shared.handlePlaybackPaused(continuousDuration: duration, averageVolume: avgVol)
            }
            lastPauseTimestamp = now
            stopSamplingTimer()
            persistCurrentState(sync: false)
        }

        onStatisticsUpdated?()
    }

    public func handleHeadphoneDisconnected() {
        if activeSession != nil {
            finalizeActiveSession(at: Date())
            stopSamplingTimer()
            self.isAudioPlaying = false
            currentContinuousPlaybackStart = nil
            continuousPlaybackDuration = 0
            persistCurrentState(sync: false)
            onStatisticsUpdated?()
        }
    }

    public func finalizeActiveSession(at timestamp: Date) {
        guard var session = activeSession else { return }
        checkMidnightRollover()

        session.complete(at: timestamp)
        self.activeSession = nil
        self.isAudioPlaying = false

        let todayKey = DailyStatistics.makeDateKey(for: Date())
        let sessionKey = DailyStatistics.makeDateKey(for: session.startTime)

        if sessionKey == todayKey {
            todayStatistics.sessions.append(session)
        } else {
            var targetStats = allDailyRecords[sessionKey] ?? DailyStatistics(calendarDate: session.startTime)
            targetStats.sessions.append(session)
            allDailyRecords[sessionKey] = targetStats
        }

        persistCurrentState(sync: false)
        onStatisticsUpdated?()
    }

    // MARK: - Sleep / Wake / Terminate Handlers

    @objc private func handleSystemWillSleep() {
        if var session = activeSession {
            session.pausePlayback(at: Date())
            self.activeSession = session
            stopSamplingTimer()
            self.isAudioPlaying = false
            persistCurrentState(sync: true)
        }
    }

    @objc private func handleSystemDidWake() {
        checkMidnightRollover()
        onStatisticsUpdated?()
    }

    @objc private func handleAppWillTerminate() {
        if activeSession != nil {
            finalizeActiveSession(at: Date())
            stopSamplingTimer()
            _ = persistence.saveSync(currentPersistedData())
        }
    }

    // MARK: - Midnight / Day Rollover

    private func startMidnightRolloverTimer() {
        midnightCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkMidnightRollover()
        }
    }

    public func checkMidnightRollover() {
        let now = Date()
        let calendar = Calendar.current
        let currentDayKey = DailyStatistics.makeDateKey(for: now, calendar: calendar)

        if todayStatistics.dateKey != currentDayKey {
            handleDayRollover(now: now, newDayKey: currentDayKey, calendar: calendar)
        }
    }

    private func handleDayRollover(now: Date, newDayKey: String, calendar: Calendar) {
        let startOfToday = calendar.startOfDay(for: now)

        // Archive yesterday's completed stats
        allDailyRecords[todayStatistics.dateKey] = todayStatistics

        // If audio was actively playing across midnight, split cleanly
        if var ongoing = activeSession {
            let endOfYesterday = startOfToday.addingTimeInterval(-0.001)
            let wasPlaying = ongoing.isAudioPlaying
            ongoing.complete(at: endOfYesterday)
            todayStatistics.sessions.append(ongoing)
            allDailyRecords[todayStatistics.dateKey] = todayStatistics

            var splitSession = ListeningSession(
                deviceUID: ongoing.deviceUID,
                deviceName: ongoing.deviceName,
                startTime: startOfToday,
                lastHeartbeat: now
            )
            if wasPlaying {
                splitSession.startPlayback(at: startOfToday)
            }
            self.activeSession = splitSession
        }

        // Fresh statistics for today
        self.todayStatistics = DailyStatistics(calendarDate: now, calendar: calendar)
        persistCurrentState(sync: true)
        onStatisticsUpdated?()
    }

    // MARK: - Periodic Sampling & Aggregation (Only during active playback)

    private func startSamplingTimer() {
        stopSamplingTimer()
        lastSampleDate = Date()

        let interval = max(1.0, settings.samplingInterval)
        samplingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleCurrentExposure()
            }
        }
    }

    private func stopSamplingTimer() {
        samplingTimer?.invalidate()
        samplingTimer = nil
        lastSampleDate = nil
    }

    @MainActor
    public func currentContinuousListeningDuration(at now: Date = Date()) -> TimeInterval {
        var total = continuousPlaybackDuration
        if let start = currentContinuousPlaybackStart {
            total += max(0, now.timeIntervalSince(start))
        }
        return total
    }

    @MainActor
    private func sampleCurrentExposure() {
        guard var session = activeSession, session.isAudioPlaying else { return }
        checkMidnightRollover()

        guard let activeDevice = BluetoothDeviceManagerDelegateProxy.shared.currentActiveHeadphone else {
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleDate ?? now)
        lastSampleDate = now

        let volume = CoreAudioBridge.shared.getVolume(for: activeDevice.id)
        guard let dbfs = decibelProvider.digitalAttenuationDBFS(volumeScalar: volume) else { return }
        // Record sample in session with measured volume
        session.recordSample(dbfs, volume: volume, at: now)

        let appName = detectActiveAudioAppName()
        session.recordAppDuration(app: appName, seconds: elapsed)
        todayStatistics.recordAppDuration(app: appName, seconds: elapsed)

        if let cal = calibrationRecordProvider?() {
            let splStatus = decibelProvider.estimateAcousticSPL(
                currentVolume: volume,
                currentDBFS: dbfs,
                isPlaying: true,
                device: activeDevice,
                calibration: cal
            )
            if case .calibrated = splStatus {
                session.recordCalibratedInterval(elapsed)
            }
        }
        self.activeSession = session

        // Record in today's hourly bucket
        let hour = Calendar.current.component(.hour, from: now)
        todayStatistics.recordHourlySample(hour: hour, dbfs: dbfs, seconds: elapsed)

        // Check continuous active playback break reminder
        let continuous = currentContinuousListeningDuration(at: now)
        if settings.breakReminderInterval > 0 && continuous >= settings.breakReminderInterval {
            postBreakReminderNotification(minutes: Int(round(continuous / 60)))
            continuousPlaybackDuration = 0
            currentContinuousPlaybackStart = now
        }

        // Periodic persist every 15 samples
        if session.sampleCount % 15 == 0 {
            persistCurrentState(sync: false)
        }

        onStatisticsUpdated?()
    }

    private func detectActiveAudioAppName() -> String {
        let knownAudioApps: [String] = [
            "Spotify", "Music", "Podcasts", "Safari", "Google Chrome", "Arc",
            "Brave Browser", "Firefox", "Logic Pro", "Ableton Live", "Reaper",
            "GarageBand", "Final Cut Pro", "DaVinci Resolve", "Zoom", "zoom.us",
            "Microsoft Teams", "Slack", "Discord", "FaceTime", "VLC", "IINA",
            "QuickTime Player", "mpv", "WhatsApp", "Telegram"
        ]

        let workspace = NSWorkspace.shared
        // 1. Check frontmost application first
        if let frontmost = workspace.frontmostApplication?.localizedName {
            if knownAudioApps.contains(where: { frontmost.localizedCaseInsensitiveContains($0) }) {
                return frontmost
            }
        }

        // 2. Check running applications for known active audio apps
        let running = workspace.runningApplications
        for known in knownAudioApps {
            if let match = running.first(where: { $0.localizedName?.localizedCaseInsensitiveContains(known) == true && !$0.isTerminated }) {
                return match.localizedName ?? known
            }
        }

        // 3. Fallback to frontmost non-system application
        if let frontmost = workspace.frontmostApplication?.localizedName, frontmost != "Finder" && frontmost != "metere" {
            return frontmost
        }

        return "System Audio"
    }

    private func postBreakReminderNotification(minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Listening Break Reminder"
        content.body = "You've been listening actively for \(minutes) minutes. Taking regular listening breaks preserves your hearing acuity."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "metere.breakReminder.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[ListeningSessionManager] Break reminder notification failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Querying & Analysis Methods

    public func getWeeklyTrend(now: Date = Date()) -> [DayTrendSummary] {
        getTrend(period: .days7, now: now)
    }

    public func getTrend(period: TrendPeriod, now: Date = Date()) -> [DayTrendSummary] {
        HistoryAnalyzer.buildTrend(
            period: period,
            todayStats: todayStatistics,
            activeSession: activeSession,
            allDailyRecords: allDailyRecords,
            now: now
        )
    }

    public func getActiveDaysPast7(now: Date = Date()) -> (active: Int, total: Int) {
        HistoryAnalyzer.calculateActiveDaysPast7(
            todayStats: todayStatistics,
            activeSession: activeSession,
            allDailyRecords: allDailyRecords,
            now: now
        )
    }

    public func getSessionsOver60mThisWeek(now: Date = Date()) -> Int {
        HistoryAnalyzer.calculateSessionsOver60mThisWeek(
            todayStats: todayStatistics,
            activeSession: activeSession,
            allDailyRecords: allDailyRecords,
            now: now
        )
    }

    public func getSessionLengthDistribution() -> SessionLengthDistribution {
        HistoryAnalyzer.calculateSessionLengthDistribution(from: getAllHistoricalSessions())
    }

    public func getTopApplications(limit: Int = 5) -> [(app: String, duration: TimeInterval, percentage: Double)] {
        todayStatistics.topApplications(activeSession: activeSession, limit: limit)
    }

    public func getPersonalBaseline() -> PersonalBaseline? {
        var records = allDailyRecords
        records[todayStatistics.dateKey] = todayStatistics
        return HistoryAnalyzer.calculateBaseline(from: records)
    }

    public func getInsights(now: Date = Date()) -> [ListeningInsight] {
        HistoryAnalyzer.generateInsights(
            todayStats: todayStatistics,
            activeSession: activeSession,
            allDailyRecords: allDailyRecords,
            now: now
        )
    }

    public func getAllHistoricalSessions() -> [ListeningSession] {
        var all: [ListeningSession] = []
        let sortedDays = allDailyRecords.values.sorted(by: { $0.calendarDate > $1.calendarDate })
        for day in sortedDays {
            if day.dateKey != todayStatistics.dateKey {
                all.append(contentsOf: day.sessions.reversed())
            }
        }
        // Prepend today's completed sessions
        all.insert(contentsOf: todayStatistics.sessions.reversed(), at: 0)
        // Prepend active session if any
        if let active = activeSession {
            all.insert(active, at: 0)
        }
        return all
    }

    public func getDeviceSummaries() -> [DeviceUsageSummary] {
        var dict: [String: DeviceUsageSummary] = [:]
        let allSessions = getAllHistoricalSessions()
        for s in allSessions {
            if var existing = dict[s.deviceUID] {
                existing.totalListeningDuration += s.activePlaybackDuration
                existing.sessionCount += 1
                dict[s.deviceUID] = existing
            } else {
                dict[s.deviceUID] = DeviceUsageSummary(
                    deviceUID: s.deviceUID,
                    deviceName: s.deviceName,
                    totalListeningDuration: s.activePlaybackDuration,
                    sessionCount: 1,
                    averageVolume: s.averageVolume
                )
            }
        }
        return Array(dict.values).sorted(by: { $0.totalListeningDuration > $1.totalListeningDuration })
    }

    // MARK: - State Persistence

    private func currentPersistedData() -> PersistedData {
        var records = allDailyRecords
        records[todayStatistics.dateKey] = todayStatistics
        return PersistedData(
            dailyRecords: records,
            activeSession: activeSession,
            lastSavedTimestamp: Date()
        )
    }

    public func persistCurrentState(sync: Bool = false) {
        let data = currentPersistedData()
        if sync {
            _ = persistence.saveSync(data)
        } else {
            persistence.saveData(data)
        }
    }

    // MARK: - Reset Actions

    public func clearTodayData() {
        let now = Date()
        self.todayStatistics = DailyStatistics(calendarDate: now)
        if var session = activeSession {
            let wasPlaying = session.isAudioPlaying
            session.complete(at: now)
            var fresh = ListeningSession(
                deviceUID: session.deviceUID,
                deviceName: session.deviceName,
                startTime: now,
                lastHeartbeat: now
            )
            if wasPlaying {
                fresh.startPlayback(at: now)
            }
            self.activeSession = fresh
        }
        persistCurrentState(sync: true)
        onStatisticsUpdated?()
    }

    public func clearAllHistory() {
        persistence.clearAll()
        self.allDailyRecords = [:]
        clearTodayData()
    }
}

public final class BluetoothDeviceManagerDelegateProxy: @unchecked Sendable {
    public static let shared = BluetoothDeviceManagerDelegateProxy()
    public var currentActiveHeadphone: AudioDevice?
    private init() {}
}
