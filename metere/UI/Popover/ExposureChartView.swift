//
//  ExposureChartView.swift
//  metere
//

import SwiftUI
import Charts

public struct ExposureChartView: View {
    let hourlyBuckets: [HourlyExposure]

    @State private var hoveredHour: HourlyExposure? = nil

    private var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today's Active Playback Timeline")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if let h = hoveredHour {
                    Text("\(formatHourRange(h.hour)): \(DailyStatistics.formattedDuration(h.listeningSeconds))\(h.averageDBFS.map { String(format: " · %.1f dBFS", $0) } ?? "")")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.accentColor)
                } else {
                    Text("24h Activity")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }

            Chart {
                ForEach(hourlyBuckets) { item in
                    let minutes = min(60.0, item.listeningSeconds / 60.0)
                    let avgDBFS = item.averageDBFS ?? -30.0

                    BarMark(
                        x: .value("Hour", item.hour),
                        y: .value("Minutes", max(1.5, minutes))
                    )
                    .foregroundStyle(barColor(for: avgDBFS, minutes: minutes, isHovered: item.hour == hoveredHour?.hour))
                    .cornerRadius(2)
                }

                // Threshold reference line at 60 minutes
                RuleMark(y: .value("Max Hour", 60))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.2))
            }
            .chartXScale(domain: 0...23)
            .chartYScale(domain: 0...60)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let hour: Int = proxy.value(atX: location.x) {
                                    let clamped = min(max(hour, 0), 23)
                                    self.hoveredHour = hourlyBuckets.first(where: { $0.hour == clamped })
                                }
                            case .ended:
                                self.hoveredHour = nil
                            }
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    if let hour = value.as(Int.self) {
                        AxisValueLabel {
                            Text(formatHourLabel(hour))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 52)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }

    private func formatHourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 6: return "6a"
        case 12: return "12p"
        case 18: return "6p"
        case 23: return "11p"
        default: return "\(hour)"
        }
    }

    private func formatHourRange(_ hour: Int) -> String {
        let nextHour = (hour + 1) % 24
        return String(format: "%02d:00–%02d:00", hour, nextHour)
    }

    private func barColor(for dbfs: Double, minutes: Double, isHovered: Bool) -> Color {
        if isHovered {
            return Color.accentColor
        }
        guard minutes > 0.5 else {
            return Color.secondary.opacity(0.12)
        }

        if dbfs >= -6.0 {
            return Color.red.opacity(0.85)
        } else if dbfs >= -12.0 {
            return Color.orange.opacity(0.85)
        } else if dbfs >= -20.0 {
            return Color.blue.opacity(0.85)
        } else {
            return Color.teal.opacity(0.85)
        }
    }
}
