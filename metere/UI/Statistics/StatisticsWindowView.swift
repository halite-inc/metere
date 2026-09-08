//
//  StatisticsWindowView.swift
//  metere
//

import SwiftUI

public enum StatisticsTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case hearing = "Hearing"
    case sessions = "Sessions"
    case devices = "Devices"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .overview: return "chart.bar.xaxis"
        case .hearing: return "ear"
        case .sessions: return "list.bullet.rectangle"
        case .devices: return "headphones"
        }
    }
}

public struct StatisticsWindowView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: StatisticsTab = .overview

    @MainActor
    public init(appState: AppState = .shared) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            List(StatisticsTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.iconName)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .navigationTitle("Statistics")
            .listStyle(.sidebar)
            .frame(minWidth: 170, idealWidth: 190, maxWidth: 220)
        } detail: {
            Group {
                switch selectedTab {
                case .overview:
                    OverviewStatisticsTab(appState: appState)
                case .hearing:
                    HearingStatisticsTab(appState: appState)
                case .sessions:
                    SessionsStatisticsTab(appState: appState)
                case .devices:
                    DevicesStatisticsTab(appState: appState)
                }
            }
            .frame(minWidth: 520, minHeight: 520)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 740, idealWidth: 840, minHeight: 560, idealHeight: 640)
    }
}

// MARK: - 1. Overview Tab

private struct OverviewStatisticsTab: View {
    @ObservedObject var appState: AppState
    @State private var selectedPeriod: TrendPeriod = .days7

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Overview")
                        .font(.system(size: 20, weight: .bold))
                    Text("How you have been using audio over time.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Today Hero Card (Dominant listening today + inline subordinate stats)
                TodayHeroCard(appState: appState)

                // Listening Trend (7D / 30D / 3M)
                ListeningTrendCard(appState: appState, selectedPeriod: $selectedPeriod)

                // Behavioral Context Strip (Active days, longest streak, extended sessions)
                BehavioralContextStrip(appState: appState)

                // Your Listening Pattern (Progressive baseline)
                PersonalListeningPatternCard(baseline: appState.personalBaseline)

                // Behavioral Insights (2-3 concise observations)
                if !appState.listeningInsights.isEmpty {
                    InsightsCard(insights: appState.listeningInsights)
                }
            }
            .padding(22)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Overview Components

private struct TodayHeroCard: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(appState.formattedTodayDuration)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("listening today")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()
            }

            // Subordinate inline statistics
            HStack(spacing: 8) {
                Text("\(appState.todaySessionCount) session\(appState.todaySessionCount == 1 ? "" : "s")")
                Text("·")
                    .foregroundColor(.secondary.opacity(0.4))
                Text("\(appState.formattedTodayAverageSession) average")
                Text("·")
                    .foregroundColor(.secondary.opacity(0.4))
                Text("\(appState.formattedTodayLongestSession) longest")

                if appState.calibratedTodayDuration > 0 {
                    Text("·")
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("\(appState.formattedCalibratedTodayDuration) calibrated")
                        .foregroundColor(.accentColor)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct ListeningTrendCard: View {
    @ObservedObject var appState: AppState
    @Binding var selectedPeriod: TrendPeriod
    @State private var hoveredDay: DayTrendSummary? = nil

    var body: some View {
        let trends = appState.trend(for: selectedPeriod)
        let maxHours = max(1.0, trends.map { $0.hours }.max() ?? 1.0)
        let hasListening = trends.contains(where: { $0.activeSeconds > 60 })

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Listening Trend")
                        .font(.system(size: 13, weight: .semibold))

                    if let h = hoveredDay {
                        Text("\(h.dateKey): \(h.formattedDuration) active playback")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.accentColor)
                    } else if !hasListening {
                        Text("Build your listening history as you use audio")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text(selectedPeriod == .days7 ? "Past 7 days" : (selectedPeriod == .days30 ? "Past 30 days" : "Past 3 months"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Compact Period Picker
                Picker("", selection: $selectedPeriod) {
                    ForEach(TrendPeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            // Compact Bar Chart
            HStack(alignment: .bottom, spacing: selectedPeriod == .days7 ? 10 : (selectedPeriod == .days30 ? 3 : 1.5)) {
                ForEach(trends) { day in
                    let isHovered = (hoveredDay?.id == day.id)
                    let barHeight = max(day.activeSeconds > 0 ? 4.0 : 2.0, (day.hours / maxHours) * 72.0)

                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(nsColor: .separatorColor).opacity(0.12))
                                .frame(height: 72)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    isHovered ? Color.accentColor :
                                    (day.isToday ? Color.accentColor : (day.activeSeconds > 0 ? Color.secondary.opacity(0.65) : Color.clear))
                                )
                                .frame(height: barHeight)
                        }

                        if selectedPeriod == .days7 {
                            Text(day.dayOfWeekLabel)
                                .font(.system(size: 10, weight: day.isToday || isHovered ? .bold : .regular))
                                .foregroundColor(day.isToday || isHovered ? .accentColor : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hoveredDay = inside ? day : nil
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct BehavioralContextStrip: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let activeDays = appState.activeDaysThisWeek
        let over60m = appState.sessionsOver60mCount

        HStack(spacing: 12) {
            BehavioralContextItem(
                label: "Active days",
                value: "\(activeDays.active) / \(activeDays.total)",
                detail: "Past 7 days"
            )
            Divider().frame(height: 28)
            BehavioralContextItem(
                label: "Longest continuous",
                value: appState.formattedTodayLongestSession,
                detail: "Today's peak"
            )
            Divider().frame(height: 28)
            BehavioralContextItem(
                label: "Sessions >60m",
                value: "\(over60m)",
                detail: "Past 7 days"
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
    }
}

private struct BehavioralContextItem: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PersonalListeningPatternCard: View {
    let baseline: PersonalBaseline?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Listening Pattern")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                if let b = baseline {
                    Text("\(b.confidence.badgeDescription) · Based on \(b.daysSampled) days")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                } else {
                    Text("Building your baseline")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color(nsColor: .separatorColor).opacity(0.15)))
                }
            }

            if let b = baseline {
                HStack(spacing: 12) {
                    PatternMetricItem(label: "Typical daily listening", value: b.formattedDailyListening)
                    PatternMetricItem(label: "Typical session length", value: b.formattedSessionDuration)
                    PatternMetricItem(label: "Typical system volume", value: b.formattedSystemVolume)
                }
                Text("Behavioral usage pattern only · Does not represent medical advice or safe thresholds")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 2)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Metere is learning your typical listening habits. At least 3 distinct days of playback are required to identify patterns. No estimates are fabricated.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .separatorColor).opacity(0.08)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct PatternMetricItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .separatorColor).opacity(0.08)))
    }
}

private struct InsightsCard: View {
    let insights: [ListeningInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insights")
                .font(.system(size: 13, weight: .semibold))

            ForEach(insights.prefix(3)) { insight in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: insight.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(insight.title)
                            .font(.system(size: 12, weight: .semibold))
                        Text(insight.message)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor).opacity(0.5)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - 2. Hearing Tab

private struct HearingStatisticsTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hearing")
                        .font(.system(size: 20, weight: .bold))
                    Text("Acoustic sound pressure and sound exposure based strictly on empirical calibration.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Primary Acoustic Status Card
                HStack(spacing: 12) {
                    // Current Acoustic Level
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Acoustic Level")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Text(acousticLevelText)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text(acousticLevelSubtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))

                    // WHO Exposure Status
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WHO Sound Exposure Dose")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Text(whoDoseText)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(whoDoseColor)

                        Text(whoDoseSubtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                }

                // Calibrated vs Uncalibrated Listening Breakdown
                VStack(alignment: .leading, spacing: 10) {
                    Text("Listening Time Breakdown")
                        .font(.system(size: 13, weight: .semibold))

                    HStack(spacing: 12) {
                        ListeningBreakdownItem(
                            label: "Total listening today",
                            value: appState.formattedTodayDuration,
                            detail: "Authoritative playback duration"
                        )
                        Divider().frame(height: 32)
                        ListeningBreakdownItem(
                            label: "Calibrated listening",
                            value: appState.formattedCalibratedTodayDuration,
                            detail: "Inside operating envelope"
                        )
                        Divider().frame(height: 32)
                        ListeningBreakdownItem(
                            label: "Uncalibrated listening",
                            value: appState.formattedUncalibratedTodayDuration,
                            detail: "Active time without calibration"
                        )
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .separatorColor).opacity(0.08)))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))

                // Auditory Recovery & Quiet Rest Recommendation
                AuditoryRestRecoveryCard(appState: appState)

                // Uncalibrated State Guidance vs Active Calibration Record
                if let cal = appState.activeCalibrationRecord {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Active Calibration Profile")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(cal.isModelLevelOnly ? "Model-level" : "Device-specific")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }

                        VStack(spacing: 7) {
                            GridRowView(label: "Device Model", value: cal.deviceModel)
                            GridRowView(label: "Device Identifier", value: cal.deviceUID)
                            GridRowView(label: "Reference Measurement", value: String(format: "%.1f dBA at %.0f%% vol (%.1f dBFS)", cal.referenceSPL, cal.calibratedVolume * 100, cal.calibratedDBFS))
                            GridRowView(label: "Operating Envelope", value: String(format: "Volume ±%.0f%% · Digital Level ±%.1f dB", cal.supportedVolumeTolerance * 100, cal.supportedDBFSTolerance))
                            GridRowView(label: "Measurement Uncertainty", value: String(format: "±%.1f dB", cal.uncertaintyDB))
                            GridRowView(label: "Methodology", value: cal.methodology.displayName)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                } else {
                    // Transparent Uncalibrated Notice
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                            Text("Acoustic Calibration Required")
                                .font(.system(size: 13, weight: .semibold))
                        }

                        Text("Metere does not currently have an acoustic calibration record for the active audio device. Active listening-time tracking continues normally without calibration.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)

                        Divider()

                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("What Metere measures")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("✓ Active listening time\n✓ Session count & duration\n✓ Digital level (dBFS)\n✓ macOS system volume (%)\n✓ Connected device telemetry")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("What requires calibration")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("• Acoustic sound pressure (dBA SPL)\n• WHO sound exposure dose (%)\n• Daily safe listening allowance\n• Decibel-based hearing metrics")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                }

                // Metrological Principles Notice
                VStack(alignment: .leading, spacing: 6) {
                    Text("Metrological Principles")
                        .font(.system(size: 12, weight: .semibold))

                    Text("• Digital signal amplitude (dBFS) measures bits relative to full scale, not acoustic ear pressure.\n• macOS volume controls internal DAC attenuation, which is non-linear across headphones.\n• WHO Reference Model: 80 dBA / 40h weekly (20,571s daily allowance, 3 dB exchange rate).\n• Zero Extrapolation: Deviating outside calibrated envelope strictly disables physical SPL estimation.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineSpacing(2.5)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .separatorColor).opacity(0.06)))
            }
            .padding(22)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var acousticLevelText: String {
        switch appState.acousticSPLStatus {
        case .calibrated(let dba, let uncertainty, _):
            return String(format: "%.1f dBA ±%.1f dB", dba, uncertainty)
        case .notMeasured:
            return "Not measured"
        }
    }

    private var acousticLevelSubtitle: String {
        switch appState.acousticSPLStatus {
        case .calibrated(_, _, let isModel):
            return isModel ? "Model-level calibration estimate" : "Device-specific calibration"
        case .notMeasured(let reason):
            return reason
        }
    }

    private var whoDoseText: String {
        switch appState.whoExposureStatus {
        case .evaluated(let dose, _, _):
            return String(format: "%.1f%%", dose)
        case .unavailable:
            return "Unavailable"
        }
    }

    private var whoDoseColor: Color {
        switch appState.whoExposureStatus {
        case .evaluated(let dose, _, _):
            if dose > 100 { return .red }
            if dose > 80 { return .orange }
            return .accentColor
        case .unavailable:
            return .secondary
        }
    }

    private var whoDoseSubtitle: String {
        switch appState.whoExposureStatus {
        case .evaluated(_, let allowance, let uncertainty):
            return String(format: "Allowance: %.1fh · Cal. uncertainty ±%.1f dB", allowance, uncertainty)
        case .unavailable(let reason):
            return reason
        }
    }
}

private struct AuditoryRestRecoveryCard: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var restManager = AuditoryRestManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: restManager.isResting ? "moon.stars.fill" : "leaf.fill")
                        .foregroundColor(restManager.isResting ? .purple : .green)
                        .font(.system(size: 14))

                    Text("Auditory Recovery & Quiet Rest")
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                if restManager.isResting {
                    Text("Quiet Rest In Progress")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.purple.opacity(0.12)))
                } else if restManager.recommendedRestSeconds > 0 && restManager.elapsedRestSeconds >= restManager.recommendedRestSeconds {
                    Text("Fully Recovered")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                } else {
                    Text("Psychoacoustic Model")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(nsColor: .separatorColor).opacity(0.12)))
                }
            }

            if restManager.recommendedRestSeconds > 0 {
                // Active recommendation state
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(restManager.isResting ? "Remaining Rest Time" : "Recommended Rest")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(restManager.isResting ? restManager.formattedRemainingRest : restManager.formattedRecommendedRest)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(restManager.isResting ? .purple : .primary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Continuous Session")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(DailyStatistics.formattedDuration(restManager.lastSessionDuration))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Progress bar
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(nsColor: .separatorColor).opacity(0.15))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(restManager.recoveryProgress))), height: 6)
                            }
                        }
                        .frame(height: 6)

                        HStack {
                            Text(String(format: "%.0f%% recovered", restManager.recoveryProgress * 100))
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(restManager.formattedElapsedRest) elapsed of \(restManager.formattedRecommendedRest)")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                // Baseline / Resting normal state
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Continuous Playback Status")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(appState.continuousListeningDuration > 0 ? "\(DailyStatistics.formattedDuration(appState.continuousListeningDuration)) active" : "Audio currently idle")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Recovery Threshold")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("25 min continuous")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            Text("Temporary threshold shifts and stereocilia metabolic fatigue accumulate during continuous headphone listening. Taking quiet breaks proportional to listening intensity (15%–40% of session time) restores auditory sensitivity and prevents cochlear strain.")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct ListeningBreakdownItem: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 3. Sessions Tab

private struct SessionsStatisticsTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header & Export Actions
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sessions")
                            .font(.system(size: 20, weight: .bold))
                        Text("24-hour activity timeline and chronological playback history.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            let csv = DataExportManager.shared.generateCSV(from: appState.historicalSessions)
                            DataExportManager.shared.presentSavePanel(defaultFilename: "metere_listening_history.csv", content: csv)
                        } label: {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                                .font(.system(size: 11.5))
                        }

                        Button {
                            let persistence = PersistenceManager.shared
                            let data = persistence.loadData()
                            if let jsonData = try? DataExportManager.shared.generateJSON(from: data) {
                                DataExportManager.shared.presentSavePanel(defaultFilename: "metere_listening_history.json", data: jsonData)
                            }
                        } label: {
                            Label("Export JSON", systemImage: "doc.text")
                                .font(.system(size: 11.5))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Today's 24-Hour Activity Timeline")
                        .font(.system(size: 13, weight: .semibold))

                    ExposureChartView(hourlyBuckets: appState.hourlyBuckets)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))

                // 7×24 Weekly Habit Heatmap
                WeeklyHabitHeatmapCard(appState: appState)

                // App-Specific Audio Attribution
                AppAudioAttributionCard(appState: appState)

                // Session Length Distribution (Compact bucket distribution)
                let dist = appState.sessionLengthDistribution
                if dist.isMeaningful {
                    SessionLengthDistributionCard(distribution: dist)
                }

                // Chronological Session History
                VStack(alignment: .leading, spacing: 10) {
                    Text("Session Log")
                        .font(.system(size: 13, weight: .semibold))

                    let sessions = appState.historicalSessions
                    if sessions.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "headphones")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary.opacity(0.4))
                            Text("No listening sessions recorded yet.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(30)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(sessions) { session in
                                DetailedSessionRow(session: session)
                            }
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(22)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct SessionLengthDistributionCard: View {
    let distribution: SessionLengthDistribution

    var body: some View {
        let maxCount = max(1, max(distribution.under15m, max(distribution.from15to30m, max(distribution.from30to60m, distribution.over60m))))

        VStack(alignment: .leading, spacing: 10) {
            Text("Session Length Distribution")
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 6) {
                DistributionBarRow(label: "<15m", count: distribution.under15m, maxCount: maxCount)
                DistributionBarRow(label: "15–30m", count: distribution.from15to30m, maxCount: maxCount)
                DistributionBarRow(label: "30–60m", count: distribution.from30to60m, maxCount: maxCount)
                DistributionBarRow(label: "60m+", count: distribution.over60m, maxCount: maxCount)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct DistributionBarRow: View {
    let label: String
    let count: Int
    let maxCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)

            GeometryReader { geo in
                let barWidth = count > 0 ? max(6.0, (CGFloat(count) / CGFloat(maxCount)) * geo.size.width) : 0.0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor).opacity(0.1))
                        .frame(height: 14)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(count > 0 ? 0.8 : 0.2))
                        .frame(width: barWidth, height: 14)
                }
            }
            .frame(height: 14)

            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

private struct DetailedSessionRow: View {
    let session: ListeningSession
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(session.isAudioPlaying ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12.5, weight: .semibold))

                        Text("·")
                            .foregroundColor(.secondary.opacity(0.4))

                        Text(session.deviceName)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(DailyStatistics.formattedDuration(session.activePlaybackDuration))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }

                    HStack(spacing: 8) {
                        Text("Source: \(session.sourceApp)")
                        if let vol = session.averageVolume {
                            Text("· System vol: \(Int(round(vol * 100)))%")
                        }
                        if let dbfs = session.averageDBFS {
                            Text(String(format: "· Avg: %.1f dBFS", dbfs))
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Divider().padding(.vertical, 2)

                VStack(spacing: 5) {
                    GridRowView(label: "Active Playback Duration", value: DailyStatistics.formattedDuration(session.activePlaybackDuration))
                    GridRowView(label: "Calibrated Duration", value: DailyStatistics.formattedDuration(session.calibratedPlaybackDuration))
                    GridRowView(label: "Uncalibrated Duration", value: DailyStatistics.formattedDuration(session.uncalibratedPlaybackDuration))

                    if let dbfs = session.averageDBFS {
                        GridRowView(label: "Average Digital Level", value: String(format: "%.1f dBFS", dbfs))
                    }
                    if let maxD = session.maxDBFS {
                        GridRowView(label: "Peak Digital Level", value: String(format: "%.1f dBFS", maxD))
                    }
                    if let vol = session.averageVolume {
                        GridRowView(label: "Average System Volume", value: "\(Int(round(vol * 100)))%")
                    }
                    GridRowView(label: "Device Identifier", value: session.deviceUID)
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }
}

// MARK: - Sessions Components (Heatmap & Attribution)

private struct WeeklyHabitHeatmapCard: View {
    @ObservedObject var appState: AppState
    @State private var hoveredCell: (day: Int, hour: Int, seconds: Double)? = nil

    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("7×24 Weekly Habit Heatmap")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Listening intensity distribution across days of the week and hours of the day.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                if let hovered = hoveredCell {
                    Text("\(dayLabels[hovered.day]) at \(String(format: "%02d:00", hovered.hour)) · \(DailyStatistics.formattedDuration(hovered.seconds))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
            }

            let matrix = appState.habitHeatmapMatrix

            VStack(spacing: 4) {
                // Hour headers
                HStack(spacing: 4) {
                    Text("")
                        .frame(width: 32)
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hour % 6 == 0 ? "\(hour)" : "")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Grid rows
                ForEach(0..<7, id: \.self) { dayIndex in
                    HStack(spacing: 4) {
                        Text(dayLabels[dayIndex])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 32, alignment: .leading)

                        ForEach(0..<24, id: \.self) { hour in
                            let seconds = dayIndex < matrix.count && hour < matrix[dayIndex].count ? matrix[dayIndex][hour] : 0.0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cellColor(for: seconds))
                                .frame(height: 16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(hoveredCell?.day == dayIndex && hoveredCell?.hour == hour ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                                .onHover { isHovered in
                                    if isHovered {
                                        hoveredCell = (day: dayIndex, hour: hour, seconds: seconds)
                                    } else if hoveredCell?.day == dayIndex && hoveredCell?.hour == hour {
                                        hoveredCell = nil
                                    }
                                }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 8) {
                Text("Less")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)

                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: .separatorColor).opacity(0.12)).frame(width: 10, height: 10)
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.25)).frame(width: 10, height: 10)
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.50)).frame(width: 10, height: 10)
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.75)).frame(width: 10, height: 10)
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 10, height: 10)
                }

                Text("More (Active Listening)")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func cellColor(for seconds: Double) -> Color {
        if seconds <= 0 {
            return Color(nsColor: .separatorColor).opacity(0.12)
        } else if seconds < 900 { // < 15 min
            return Color.accentColor.opacity(0.25)
        } else if seconds < 1800 { // 15-30 min
            return Color.accentColor.opacity(0.50)
        } else if seconds < 2700 { // 30-45 min
            return Color.accentColor.opacity(0.75)
        } else { // 45-60 min
            return Color.accentColor
        }
    }
}

private struct AppAudioAttributionCard: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("App-Specific Audio Attribution")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Today")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            let topApps = appState.topApplications

            if topApps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "app.badge")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No application audio recorded today yet.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(topApps, id: \.app) { item in
                        VStack(spacing: 4) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: appIcon(for: item.app))
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 14)

                                    Text(item.app)
                                        .font(.system(size: 12, weight: .medium))
                                }

                                Spacer()

                                Text(DailyStatistics.formattedDuration(item.duration))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))

                                Text(String(format: "(%.0f%%)", item.percentage * 100))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(nsColor: .separatorColor).opacity(0.15))
                                        .frame(height: 5)

                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: max(4, min(geo.size.width, geo.size.width * CGFloat(item.percentage))), height: 5)
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func appIcon(for appName: String) -> String {
        let lower = appName.lowercased()
        if lower.contains("spotify") || lower.contains("music") || lower.contains("tidal") {
            return "music.note"
        } else if lower.contains("safari") || lower.contains("chrome") || lower.contains("arc") || lower.contains("firefox") || lower.contains("brave") {
            return "globe"
        } else if lower.contains("zoom") || lower.contains("meet") || lower.contains("teams") || lower.contains("slack") {
            return "video"
        } else if lower.contains("logic") || lower.contains("ableton") || lower.contains("pro tools") || lower.contains("reaper") {
            return "waveform"
        } else if lower.contains("podcast") {
            return "antenna.radiowaves.left.and.right"
        } else if lower.contains("youtube") || lower.contains("vlc") || lower.contains("quicktime") {
            return "play.rectangle.fill"
        }
        return "app.fill"
    }
}

// MARK: - 4. Devices Tab

private struct DevicesStatisticsTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Devices")
                        .font(.system(size: 20, weight: .bold))
                    Text("Connected and historical audio output devices.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Currently Active Device
                if let active = appState.activeHeadphone {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(active.name, systemImage: active.sfSymbolName)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text("Connected Now")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(Color.green.opacity(0.12)))
                        }

                        Divider()

                        GridRowView(label: "CoreAudio Identifier", value: active.uid)
                        GridRowView(label: "Manufacturer", value: active.manufacturer ?? "Unknown")
                        GridRowView(label: "Transport Type", value: active.transportType.rawValue.capitalized)

                        // Battery Telemetry
                        if let battery = appState.batteryInfo {
                            Divider()
                            Text("Battery Telemetry")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 12) {
                                if let l = battery.leftLevel {
                                    BatteryIndicator(label: "Left", level: l)
                                }
                                if let r = battery.rightLevel {
                                    BatteryIndicator(label: "Right", level: r)
                                }
                                if let c = battery.caseLevel {
                                    BatteryIndicator(label: "Case", level: c)
                                }
                                if battery.leftLevel == nil && battery.rightLevel == nil {
                                    BatteryIndicator(label: "Headphones", level: battery.level)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                }

                // Device Usage History Breakdown
                VStack(alignment: .leading, spacing: 10) {
                    Text("Device Usage History")
                        .font(.system(size: 13, weight: .semibold))

                    let summaries = appState.deviceSummaries
                    if summaries.isEmpty {
                        Text("No device history recorded.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(12)
                    } else {
                        ForEach(summaries) { summary in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.deviceName)
                                        .font(.system(size: 12.5, weight: .medium))
                                    Text("\(summary.sessionCount) sessions · Typical system volume: \(summary.formattedVolume)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(summary.formattedDuration)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))

                                    let isCalibrated = (appState.activeCalibrationRecord?.deviceUID == summary.deviceUID)
                                    Text(isCalibrated ? "Calibrated" : "Uncalibrated")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(isCalibrated ? .accentColor : .secondary)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor).opacity(0.5)))
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(22)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Helper Views

private struct GridRowView: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
        }
    }
}

private struct BatteryIndicator: View {
    let label: String
    let level: Int

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: sfSymbol(for: level))
                .font(.system(size: 15))
                .foregroundColor(level <= 20 ? .red : .accentColor)
            Text("\(level)%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 48)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .separatorColor).opacity(0.1)))
    }

    private func sfSymbol(for level: Int) -> String {
        if level >= 90 { return "battery.100" }
        if level >= 65 { return "battery.75" }
        if level >= 40 { return "battery.50" }
        if level >= 15 { return "battery.25" }
        return "battery.0"
    }
}
