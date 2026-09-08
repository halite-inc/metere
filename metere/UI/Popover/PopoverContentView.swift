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
        VStack(spacing: 11) {
            // MARK: - Header: Refined Device & Playback Status
            DeviceHeaderView(appState: appState)

            // MARK: - Update Notification Banner (Subtle & Native)
            if updateManager.hasUpdateAvailable, let update = updateManager.availableUpdate {
                Button {
                    updateManager.showingUpdateSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)

                        Text("Update Available: v\(update.version.description)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
            }

            // Hairline separator below header
            Divider()
                .opacity(0.4)
                .padding(.horizontal, 2)

            // MARK: - Hero Metric, Session, Volume, Exposure & Navigation
            MetricsGridCard(appState: appState) {
                openStatisticsWindow()
            }

            // Hairline separator above footer
            Divider()
                .opacity(0.4)
                .padding(.horizontal, 2)

            // MARK: - Compact Utility Footer
            HStack(spacing: 4) {
                Spacer()

                PopoverHoverIconButton(
                    systemName: "gearshape",
                    size: 12,
                    helpText: "Settings… (⌘,)"
                ) {
                    openSettingsWindow()
                }

                PopoverHoverIconButton(
                    systemName: "power",
                    size: 11,
                    helpText: "Quit Metere (⌘Q)"
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 320)
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

// MARK: - Native macOS Hover Icon Button

private struct PopoverHoverIconButton: View {
    let systemName: String
    let size: CGFloat
    let helpText: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .regular))
                .foregroundColor(isHovering ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovering ? Color(nsColor: .separatorColor).opacity(0.14) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
