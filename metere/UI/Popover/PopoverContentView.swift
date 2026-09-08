//
//  PopoverContentView.swift
//  metere
//

import SwiftUI

public struct PopoverContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updateManager: UpdateManager = .shared
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    public init(appState: AppState = .shared, updateManager: UpdateManager = .shared) {
        self.appState = appState
        self.updateManager = updateManager
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header: Device & Connection/Playback Status
            DeviceHeaderView(appState: appState)

            // Update Notification Banner
            if updateManager.hasUpdateAvailable, let update = updateManager.availableUpdate {
                Button {
                    updateManager.showingUpdateSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundColor(.white)

                        Text("Update Available: v\(update.version.description)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            // Hero Metric & Glanceable Status
            MetricsGridCard(appState: appState) {
                openStatisticsWindow()
            }

            // Compact Utility Footer
            HStack {
                Spacer()

                Button {
                    openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings… (⌘,)")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit Metere (⌘Q)")
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 285)
        .background(.regularMaterial)
        .sheet(isPresented: $updateManager.showingUpdateSheet) {
            UpdateSheetView(updateManager: updateManager)
        }
    }

    private func openStatisticsWindow() {
        openWindow(id: "statistics")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.title.contains("Statistics") }) {
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func openSettingsWindow() {
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.title.contains("Settings") || $0.title.contains("Preferences") }) {
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
