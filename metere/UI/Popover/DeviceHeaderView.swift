//
//  DeviceHeaderView.swift
//  metere
//

import SwiftUI

public struct DeviceHeaderView: View {
    @ObservedObject var appState: AppState
    @State private var isPulsing = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Subtle, restrained device icon container
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .separatorColor).opacity(0.12))
                    .frame(width: 30, height: 30)

                Image(systemName: appState.menuBarSymbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(appState.isHeadphoneConnected ? .primary : .secondary)
            }

            // Device Name and Connection/Playback Status
            VStack(alignment: .leading, spacing: 2) {
                Text(deviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    statusIndicator

                    Text(statusText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            // Optional subtle inline battery indicator
            if let battery = appState.batteryInfo {
                HStack(spacing: 3) {
                    Image(systemName: battery.sfSymbolName)
                        .font(.system(size: 11))
                    Text(battery.formattedText)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                }
                .foregroundColor(.secondary)
            }
        }
        .onAppear {
            if appState.isAudioPlaying {
                isPulsing = true
            }
        }
        .onChange(of: appState.isAudioPlaying) { isPlaying in
            withAnimation(.easeInOut(duration: 1.2)) {
                isPulsing = isPlaying
            }
        }
    }

    private var deviceName: String {
        if let headphone = appState.activeHeadphone {
            return headphone.name
        }
        if let defaultDev = appState.currentDefaultDevice {
            return defaultDev.name
        }
        return "No Headphones"
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if !appState.isHeadphoneConnected {
            // Disconnected: clean hollow circle
            Circle()
                .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.2)
                .frame(width: 6, height: 6)
        } else if appState.isAudioPlaying {
            // Connected · Playing: gentle green dot with subtle breathing
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .opacity(isPulsing ? 0.65 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: isPulsing
                )
        } else if appState.activeSessionDuration > 0 {
            // Connected · Paused: steady warm amber
            Circle()
                .fill(Color.orange.opacity(0.85))
                .frame(width: 6, height: 6)
        } else {
            // Connected · No Audio: subtle neutral dot
            Circle()
                .fill(Color.secondary.opacity(0.55))
                .frame(width: 6, height: 6)
        }
    }

    private var statusText: String {
        guard appState.isHeadphoneConnected else {
            return "Disconnected"
        }
        if appState.isAudioPlaying {
            return "Connected · Playing"
        } else if appState.activeSessionDuration > 0 {
            return "Connected · Paused"
        } else {
            return "Connected · No Audio"
        }
    }
}
