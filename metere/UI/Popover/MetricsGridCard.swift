//
//  MetricsGridCard.swift
//  metere
//

import SwiftUI

public struct MetricsGridCard: View {
    @ObservedObject var appState: AppState
    var onViewStatistics: () -> Void

    public init(appState: AppState, onViewStatistics: @escaping () -> Void = {}) {
        self.appState = appState
        self.onViewStatistics = onViewStatistics
    }

    public var body: some View {
        VStack(spacing: 14) {
            // Hero Metric: Listening Today
            VStack(spacing: 2) {
                Text(appState.formattedTodayDuration)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)

                Text("Listening today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            // Current Active Session
            VStack(spacing: 2) {
                Text("Current session")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)

                Text(appState.formattedCurrentSession)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(appState.isAudioPlaying ? .primary : .secondary)
            }

            // Compact Secondary Audio Info
            HStack(spacing: 6) {
                Text("Volume \(appState.systemVolumePercentage)%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text("·")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.4))

                Text(appState.formattedDigitalLevel)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.12))
            )

            // Subtle Divider
            Divider()
                .opacity(0.5)
                .padding(.horizontal, 4)

            // Compact Hearing Exposure Summary
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Hearing Exposure")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                HStack {
                    Text(hearingStatusSummary)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(hearingStatusColor)
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
            )

            // View Statistics Navigation Button
            Button {
                onViewStatistics()
            } label: {
                HStack {
                    Text("View Statistics")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var hearingStatusSummary: String {
        switch appState.whoExposureStatus {
        case .evaluated(let dose, _, let uncertainty):
            if case .calibrated(let spl, _, _) = appState.acousticSPLStatus {
                return String(format: "%.0f dBA ±%.0fdB · %.0f%% WHO dose", spl, uncertainty, dose)
            }
            return String(format: "%.0f%% WHO dose", dose)
        case .unavailable(let reason):
            if reason.contains("envelope") {
                return "Not measured · Conditions exceeded"
            } else if reason.contains("No audio") {
                return "Not measured · Idle"
            }
            return "Not measured · Calibration required"
        }
    }

    private var hearingStatusColor: Color {
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
