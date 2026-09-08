//
//  DeviceHeaderView.swift
//  metere
//

import SwiftUI

public struct DeviceHeaderView: View {
    @ObservedObject var appState: AppState

    public var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(appState.isHeadphoneConnected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.10))
                    .frame(width: 36, height: 36)

                Image(systemName: appState.menuBarSymbolName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(appState.isHeadphoneConnected ? .accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(appState.activeHeadphone?.name ?? (appState.currentDefaultDevice?.name ?? "No Headphones"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6, height: 6)

                    Text(appState.headerPlaybackStatusText)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }

    private var statusDotColor: Color {
        guard appState.isHeadphoneConnected else {
            return Color.secondary.opacity(0.4)
        }
        if appState.isAudioPlaying {
            return Color.green
        } else if appState.activeSessionDuration > 0 {
            return Color.orange.opacity(0.85)
        } else {
            return Color.secondary.opacity(0.5)
        }
    }
}
