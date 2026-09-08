//
//  HistoryAnalyzer.swift
//  metere
//

import Foundation

public enum BaselineConfidence: String, Codable, Equatable, Sendable {
    case insufficient = "Insufficient history"
    case earlyPattern = "Early pattern"
    case initialBaseline = "Initial baseline"
    case establishedBaseline = "Established baseline"

    public var badgeDescription: String {
        switch self {
        case .insufficient: return "Insufficient history"
        case .earlyPattern: return "Early pattern"
        case .initialBaseline: return "Initial baseline"
        case .establishedBaseline: return "Established baseline"
        }
    }
}

public struct PersonalBaseline: Equatable, Sendable {
    public let typicalDailyListening: TimeInterval
    public let typicalSessionDuration: TimeInterval
    public let typicalVolume: Float
    public let typicalDBFS: Double
    public let daysSampled: Int

    public init(
        typicalDailyListening: TimeInterval,
        typicalSessionDuration: TimeInterval,
        typicalVolume: Float,
        typicalDBFS: Double,
        daysSampled: Int
    ) {
        self.typicalDailyListening = typicalDailyListening
        self.typicalSessionDuration = typicalSessionDuration
        self.typicalVolume = typicalVolume
        self.typicalDBFS = typicalDBFS
        self.daysSampled = daysSampled
    }

    public var confidence: BaselineConfidence {
        if daysSampled >= 14 {
            return .establishedBaseline
        } else if daysSampled >= 7 {
            return .initialBaseline
        } else if daysSampled >= 3 {
            return .earlyPattern
        } else {
            return .insufficient
        }
    }

    public var formattedDailyListening: String {
        DailyStatistics.formattedDuration(typicalDailyListening)
    }

    public var formattedSessionDuration: String {
        DailyStatistics.formattedDuration(typicalSessionDuration)
    }

    public var formattedVolume: String {
        "\(Int(round(typicalVolume * 100)))%"
    }

    public var formattedSystemVolume: String {
        "\(Int(round(typicalVolume * 100)))%"
    }

    public var formattedDBFS: String {
        String(format: "%.1f dBFS", typicalDBFS)
    }

    public var formattedDigitalLevel: String {
        String(format: "%.1f dBFS", typicalDBFS)
    }
}

public enum TrendPeriod: String, CaseIterable, Identifiable, Sendable {
    case days7 = "7D"
    case days30 = "30D"
    case days90 = "3M"

    public var id: String { rawValue }

    public var dayCount: Int {
        switch self {
        case .days7: return 7
        case .days30: return 30
        case .days90: return 90
        }
    }
}

public struct SessionLengthDistribution: Equatable, Sendable {
    public let under15m: Int
    public let from15to30m: Int
    public let from30to60m: Int
    public let over60m: Int
    public let totalSessions: Int

    public var isMeaningful: Bool {
        totalSessions >= 3
    }

    public init(under15m: Int, from15to30m: Int, from30to60m: Int, over60m: Int) {
        self.under15m = under15m
        self.from15to30m = from15to30m
        self.from30to60m = from30to60m
        self.over60m = over60m
        self.totalSessions = under15m + from15to30m + from30to60m + over60m
    }
}

public struct ListeningInsight: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let iconName: String
    public let title: String
    public let message: String

    public init(iconName: String, title: String, message: String) {
        self.iconName = iconName
        self.title = title
        self.message = message
    }
}

public struct DayTrendSummary: Identifiable, Equatable, Sendable {
    public var id: String { dateKey }
    public let dateKey: String
    public let dayOfWeekLabel: String // e.g. "Mon", "Tue"
    public let activeSeconds: Double
    public let isToday: Bool

    public var formattedDuration: String {
        DailyStatistics.formattedDuration(activeSeconds)
    }

    public var hours: Double {
        activeSeconds / 3600.0
    }
}

public final class HistoryAnalyzer {
    /// Minimum distinct recorded days with active playback required to calculate an empirical baseline
    public static let minimumDaysRequiredForBaseline = 3

    /// Calculates personal baseline from historical daily records. Returns nil if history is insufficient.
    public static func calculateBaseline(from dailyRecords: [String: DailyStatistics]) -> PersonalBaseline? {
        let daysWithListening = dailyRecords.values.filter { $0.totalListeningDuration() > 60 } // at least 1 min
        guard daysWithListening.count >= minimumDaysRequiredForBaseline else {
            return nil
        }

        var totalDailyTime: TimeInterval = 0
        var allSessionDurations: [TimeInterval] = []
        var totalVolumeSum: Float = 0
        var totalVolumeSamples: Int = 0
        var totalDBFSSum: Double = 0
        var totalDBFSSamples: Int = 0

        for day in daysWithListening {
            totalDailyTime += day.totalListeningDuration()

            for session in day.sessions {
                let dur = session.activePlaybackDuration
                if dur > 30 {
                    allSessionDurations.append(dur)
                }
                if let avgVol = session.averageVolume, session.sampleVolumeCount > 0 {
                    totalVolumeSum += avgVol * Float(session.sampleVolumeCount)
                    totalVolumeSamples += session.sampleVolumeCount
                }
                totalDBFSSum += session.sumDBFS
                totalDBFSSamples += session.sampleCount
            }
        }

        let avgDaily = totalDailyTime / Double(daysWithListening.count)
        let avgSession = allSessionDurations.isEmpty ? 0 : (allSessionDurations.reduce(0, +) / Double(allSessionDurations.count))
        let avgVol = totalVolumeSamples > 0 ? (totalVolumeSum / Float(totalVolumeSamples)) : 0.50
        let avgDBFS = totalDBFSSamples > 0 ? (totalDBFSSum / Double(totalDBFSSamples)) : -18.0

        return PersonalBaseline(
            typicalDailyListening: avgDaily,
            typicalSessionDuration: avgSession,
            typicalVolume: avgVol,
            typicalDBFS: avgDBFS,
            daysSampled: daysWithListening.count
        )
    }

    /// Generates deterministic observations based strictly on personal listening habits. Never makes medical claims.
    public static func generateInsights(
        todayStats: DailyStatistics,
        activeSession: ListeningSession?,
        allDailyRecords: [String: DailyStatistics],
        now: Date = Date()
    ) -> [ListeningInsight] {
        var insights: [ListeningInsight] = []
        let todayDuration = todayStats.totalListeningDuration(activeSession: activeSession, now: now)

        // 1. Comparison to 7-day average
        let calendar = Calendar.current
        var past7DayDurations: [TimeInterval] = []
        for daysAgo in 1...7 {
            if let targetDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) {
                let key = DailyStatistics.makeDateKey(for: targetDate, calendar: calendar)
                if let record = allDailyRecords[key] {
                    past7DayDurations.append(record.totalListeningDuration())
                }
            }
        }

        if !past7DayDurations.isEmpty {
            let avgPast7 = past7DayDurations.reduce(0, +) / Double(past7DayDurations.count)
            if avgPast7 > 300 { // at least 5 mins avg
                let diffPercent = Int(round(((todayDuration - avgPast7) / avgPast7) * 100))
                if diffPercent <= -15 {
                    insights.append(ListeningInsight(
                        iconName: "arrow.down.right",
                        title: "Lower Daily Listening",
                        message: "Your listening time is \(abs(diffPercent))% lower than your previous 7-day average."
                    ))
                } else if diffPercent >= 20 {
                    insights.append(ListeningInsight(
                        iconName: "arrow.up.right",
                        title: "Higher Daily Listening",
                        message: "Your listening time is \(diffPercent)% higher than your previous 7-day average."
                    ))
                }
            }
        }

        // 2. Extended continuous sessions this week
        var longSessionsCount = 0
        var maxSessionDuration: TimeInterval = 0
        let combinedSessions = todayStats.sessions + (activeSession.map { [$0] } ?? [])
        for session in combinedSessions {
            let dur = session.duration(at: now)
            if dur > 3600 { // > 60 mins
                longSessionsCount += 1
            }
            if dur > maxSessionDuration {
                maxSessionDuration = dur
            }
        }

        if longSessionsCount > 0 {
            insights.append(ListeningInsight(
                iconName: "timer",
                title: "Extended Sessions",
                message: "You had \(longSessionsCount) session\(longSessionsCount == 1 ? "" : "s") longer than 60 minutes today."
            ))
        }

        if maxSessionDuration >= 1800 {
            insights.append(ListeningInsight(
                iconName: "clock.badge.checkmark",
                title: "Longest Session",
                message: "Your longest continuous session today was \(DailyStatistics.formattedDuration(maxSessionDuration))."
            ))
        }

        // 3. Fallback for new profiles
        if insights.isEmpty {
            insights.append(ListeningInsight(
                iconName: "chart.bar",
                title: "Habit Tracking Active",
                message: "Listening duration and digital signal attenuation are logged strictly during active playback."
            ))
        }

        return insights
    }

    /// Builds rolling trend summaries for the requested period ending today
    public static func buildTrend(
        period: TrendPeriod,
        todayStats: DailyStatistics,
        activeSession: ListeningSession?,
        allDailyRecords: [String: DailyStatistics],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayTrendSummary] {
        var results: [DayTrendSummary] = []
        let dayCount = period.dayCount

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = dayCount <= 7 ? "EEE" : "d"
        weekdayFormatter.calendar = calendar

        let todayKey = DailyStatistics.makeDateKey(for: now, calendar: calendar)

        for daysAgo in (0..<dayCount).reversed() {
            guard let targetDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let key = DailyStatistics.makeDateKey(for: targetDate, calendar: calendar)
            let isToday = (key == todayKey)
            let label = weekdayFormatter.string(from: targetDate)

            let duration: TimeInterval
            if isToday {
                duration = todayStats.totalListeningDuration(activeSession: activeSession, now: now)
            } else if let record = allDailyRecords[key] {
                duration = record.totalListeningDuration()
            } else {
                duration = 0
            }

            results.append(DayTrendSummary(
                dateKey: key,
                dayOfWeekLabel: label,
                activeSeconds: duration,
                isToday: isToday
            ))
        }

        return results
    }

    /// Builds rolling 7-day trend summaries ending today (backwards compatibility)
    public static func buildWeeklyTrend(
        todayStats: DailyStatistics,
        activeSession: ListeningSession?,
        allDailyRecords: [String: DailyStatistics],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayTrendSummary] {
        buildTrend(
            period: .days7,
            todayStats: todayStats,
            activeSession: activeSession,
            allDailyRecords: allDailyRecords,
            now: now,
            calendar: calendar
        )
    }

    /// Calculates session length distribution from historical sessions
    public static func calculateSessionLengthDistribution(from sessions: [ListeningSession]) -> SessionLengthDistribution {
        var u15 = 0
        var f15_30 = 0
        var f30_60 = 0
        var o60 = 0

        for s in sessions {
            let dur = s.activePlaybackDuration
            if dur < 900 {
                u15 += 1
            } else if dur < 1800 {
                f15_30 += 1
            } else if dur < 3600 {
                f30_60 += 1
            } else {
                o60 += 1
            }
        }

        return SessionLengthDistribution(under15m: u15, from15to30m: f15_30, from30to60m: f30_60, over60m: o60)
    }

    /// Calculates active listening days in the past 7 days (e.g. active: 5, total: 7)
    public static func calculateActiveDaysPast7(
        todayStats: DailyStatistics,
        activeSession: ListeningSession?,
        allDailyRecords: [String: DailyStatistics],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (active: Int, total: Int) {
        var activeCount = 0
        let todayKey = DailyStatistics.makeDateKey(for: now, calendar: calendar)

        for daysAgo in 0..<7 {
            guard let targetDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let key = DailyStatistics.makeDateKey(for: targetDate, calendar: calendar)
            let dur: TimeInterval
            if key == todayKey {
                dur = todayStats.totalListeningDuration(activeSession: activeSession, now: now)
            } else if let record = allDailyRecords[key] {
                dur = record.totalListeningDuration()
            } else {
                dur = 0
            }
            if dur > 60 { // at least 1 min
                activeCount += 1
            }
        }
        return (active: activeCount, total: 7)
    }

    /// Counts sessions over 60m this week
    public static func calculateSessionsOver60mThisWeek(
        todayStats: DailyStatistics,
        activeSession: ListeningSession?,
        allDailyRecords: [String: DailyStatistics],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        var count = 0
        let todayKey = DailyStatistics.makeDateKey(for: now, calendar: calendar)

        for daysAgo in 0..<7 {
            guard let targetDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let key = DailyStatistics.makeDateKey(for: targetDate, calendar: calendar)
            let sessions: [ListeningSession]
            if key == todayKey {
                sessions = todayStats.sessions + (activeSession.map { [$0] } ?? [])
            } else if let record = allDailyRecords[key] {
                sessions = record.sessions
            } else {
                sessions = []
            }
            count += sessions.filter { $0.duration(at: now) >= 3600 }.count
        }
        return count
    }
}
