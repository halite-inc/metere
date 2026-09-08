//
//  MetricsGridCard.swift
//  metere
//

import SwiftUI

public struct MetricsGridCard: View {
    @ObservedObject var appState: AppState
    var onViewStatistics: () -> Void

    @State private var isHoveringStatistics = false

    public init(appState: AppState, onViewStatistics: @escaping () -> Void = {}) {
        self.appState = appState
        self.onViewStatistics = onViewStatistics
    }

    public var body: some View {
        VStack(spacing: 12) {
            // MARK: - Hero Metric: Listening Today
            VStack(spacing: 3) {
                Text(appState.formattedTodayDuration)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)

                Text("Listening today")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            // Minimal, calm grounding accent
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.25))
                .frame(width: 42, height: 1)
                .padding(.vertical, 2)

            // MARK: - Current Active Session
            VStack(spacing: 2) {
                Text("Current session")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)

                HStack(spacing: 5) {
                    if appState.isPlayingOrActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 4.5, height: 4.5)
                    }

                    Text(currentSessionText)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(appState.isPlayingOrActive ? .primary : .secondary)
                }
            }

            // MARK: - Compact Metadata Row: Volume & Digital Level
            HStack(spacing: 4) {
                Text(volumeText)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 2)

            // Hairline separator
            Divider()
                .opacity(0.4)
                .padding(.horizontal, 2)
                .padding(.vertical, 2)

            // MARK: - Hearing Exposure Summary (Intelligent 2-Line Hierarchy)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "ear")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("HEARING EXPOSURE")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundColor(.secondary.opacity(0.7))

                HStack(alignment: .firstTextBaseline) {
                    Text(hearingPrimaryStatus)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(hearingPrimaryColor)

                    Spacer()

                    Text(hearingSecondaryDetail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)

            // Hairline separator
            Divider()
                .opacity(0.4)
                .padding(.horizontal, 2)
                .padding(.vertical, 2)

            // MARK: - View Statistics (Native macOS Navigation Row)
            Button(action: onViewStatistics) {
                HStack {
                    Text("View Statistics")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHoveringStatistics ? Color(nsColor: .separatorColor).opacity(0.14) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHoveringStatistics = hovering
                }
            }
        }
    }

    // MARK: - Formatters & Computed Helpers

    private var currentSessionText: String {
        guard appState.isHeadphoneConnected else { return "—" }
        if appState.isAudioPlaying {
            return DailyStatistics.formattedDuration(appState.activeSessionDuration)
        } else if appState.activeSessionDuration > 0 {
            return "Paused"
        } else {
            return "—"
        }
    }

    private var volumeText: String {
        guard appState.isHeadphoneConnected else {
            return "Volume —"
        }
        let vol = "\(appState.systemVolumePercentage)%"
        if appState.isAudioPlaying, let dbfs = appState.digitalLevelDBFS {
            return String(format: "Volume %@  ·  Digital %.1f dBFS", vol, dbfs)
        } else {
            return "Volume \(vol)  ·  Digital Idle"
        }
    }

    private var hearingPrimaryStatus: String {
        switch appState.whoExposureStatus {
        case .evaluated(_, _, let uncertainty):
            if case .calibrated(let spl, _, _) = appState.acousticSPLStatus {
                return String(format: "%.0f dBA ±%.0fdB", spl, uncertainty)
            }
            return "Calibrated"
        case .unavailable:
            return "Not measured"
        }
    }

    private var hearingSecondaryDetail: String {
        switch appState.whoExposureStatus {
        case .evaluated(let dose, _, _):
            return String(format: "%.0f%% WHO dose", dose)
        case .unavailable(let reason):
            if reason.contains("No audio") {
                return "No active audio"
            } else if reason.contains("envelope") {
                return "Operating conditions exceeded"
            } else {
                return "Calibration required"
            }
        }
    }

    private var hearingPrimaryColor: Color {
        switch appState.whoExposureStatus {
        case .evaluated(let dose, _, _):
            if dose > 100 { return .red }
            if dose > 80 { return .orange }
            return .green
        case .unavailable:
            return .secondary
        }
    }
}
