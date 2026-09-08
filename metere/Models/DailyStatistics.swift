//
//  DailyStatistics.swift
//  metere
//

import Foundation

public struct HourlyExposure: Identifiable, Codable, Sendable {
    public var id: Int { hour }
    public let hour: Int // 0 to 23
    public var listeningSeconds: Double
    public var sumDBFS: Double
    public var sampleCount: Int

    public init(hour: Int, listeningSeconds: Double = 0, sumDBFS: Double = 0, sampleCount: Int = 0) {
        self.hour = hour
        self.listeningSeconds = listeningSeconds
        self.sumDBFS = sumDBFS
        self.sampleCount = sampleCount
    }

    public var averageDBFS: Double? {
        guard sampleCount > 0 else { return nil }
        return sumDBFS / Double(sampleCount)
    }
}

public struct DailyStatistics: Identifiable, Codable, Sendable {
    public var id: String { dateKey }
    public let dateKey: String // e.g. "2026-09-07"
    public let calendarDate: Date
    public var sessions: [ListeningSession]
    public var hourlyBuckets: [HourlyExposure] // 24 entries (0...23)
    public var appDurations: [String: TimeInterval]

    public init(calendarDate: Date = Date(), calendar: Calendar = .current) {
        let startOfDay = calendar.startOfDay(for: calendarDate)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        self.dateKey = formatter.string(from: startOfDay)
        self.calendarDate = startOfDay
        self.sessions = []
        self.hourlyBuckets = (0..<24).map { HourlyExposure(hour: $0) }
        self.appDurations = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case dateKey, calendarDate, sessions, hourlyBuckets, appDurations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dateKey = try container.decode(String.self, forKey: .dateKey)
        if let date = try container.decodeIfPresent(Date.self, forKey: .calendarDate) {
            self.calendarDate = date
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            self.calendarDate = formatter.date(from: self.dateKey) ?? Date()
        }
        self.sessions = try container.decodeIfPresent([ListeningSession].self, forKey: .sessions) ?? []
        self.hourlyBuckets = try container.decodeIfPresent([HourlyExposure].self, forKey: .hourlyBuckets) ?? (0..<24).map { HourlyExposure(hour: $0) }
        self.appDurations = try container.decodeIfPresent([String: TimeInterval].self, forKey: .appDurations) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dateKey, forKey: .dateKey)
        try container.encode(calendarDate, forKey: .calendarDate)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(hourlyBuckets, forKey: .hourlyBuckets)
        try container.encode(appDurations, forKey: .appDurations)
    }

    public static func makeDateKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: calendar.startOfDay(for: date))
    }

    /// Total listening duration today (strictly during active audio playback)
    public func totalListeningDuration(activeSession: ListeningSession? = nil, now: Date = Date()) -> TimeInterval {
        var total: TimeInterval = 0
        for session in sessions {
            total += session.duration(at: now)
        }
        if let active = activeSession, active.isActive {
            total += active.duration(at: now)
        }
        return total
    }

    /// Total calibrated listening duration today (active playback strictly inside valid calibration envelope)
    public func totalCalibratedListeningDuration(activeSession: ListeningSession? = nil) -> TimeInterval {
        var total: TimeInterval = 0
        for session in sessions {
            total += session.calibratedPlaybackDuration
        }
        if let active = activeSession {
            total += active.calibratedPlaybackDuration
        }
        return total
    }

    /// Total uncalibrated listening duration today
    public func totalUncalibratedListeningDuration(activeSession: ListeningSession? = nil, now: Date = Date()) -> TimeInterval {
        let full = totalListeningDuration(activeSession: activeSession, now: now)
        let calibrated = totalCalibratedListeningDuration(activeSession: activeSession)
        return max(0, full - calibrated)
    }

    /// Overall average digital attenuation (dBFS) for today during playback
    public func averageDBFS(activeSession: ListeningSession? = nil) -> Double? {
        var totalDBFS: Double = 0
        var totalSamples: Int = 0

        for session in sessions {
            totalDBFS += session.sumDBFS
            totalSamples += session.sampleCount
        }

        if let active = activeSession {
            totalDBFS += active.sumDBFS
            totalSamples += active.sampleCount
        }

        guard totalSamples > 0 else { return nil }
        return totalDBFS / Double(totalSamples)
    }

    /// Total number of listening sessions recorded today
    public func totalSessionCount(activeSession: ListeningSession? = nil) -> Int {
        var count = sessions.count
        if activeSession != nil {
            count += 1
        }
        return count
    }

    /// Record a sample into the hourly bucket for exposure visualization
    public mutating func recordHourlySample(hour: Int, dbfs: Double, seconds: Double) {
        guard hour >= 0 && hour < hourlyBuckets.count else { return }
        hourlyBuckets[hour].listeningSeconds += seconds
        hourlyBuckets[hour].sumDBFS += dbfs
        hourlyBuckets[hour].sampleCount += 1
    }

    /// Records playback time attributed to a specific macOS application
    public mutating func recordAppDuration(app: String, seconds: TimeInterval) {
        let clean = app.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        self.appDurations[clean, default: 0] += seconds
    }

    /// Top listening applications for today with duration and percentage of total listening
    public func topApplications(activeSession: ListeningSession? = nil, limit: Int = 5) -> [(app: String, duration: TimeInterval, percentage: Double)] {
        var combined = appDurations
        if let active = activeSession {
            for (app, dur) in active.appDurations {
                combined[app, default: 0] += dur
            }
        }
        let total = combined.values.reduce(0, +)
        guard total > 0 else { return [] }

        return combined
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (app: $0.key, duration: $0.value, percentage: $0.value / total) }
    }

    /// Clean human-readable formatted duration (e.g., "3h 42m", "25m", "< 1m", "0m")
    public static func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        if totalMinutes < 1 {
            if seconds > 0 {
                return "< 1m"
            }
            return "0m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else {
            return "\(minutes)m"
        }
    }
}
