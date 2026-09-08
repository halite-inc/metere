//
//  UpdateSheetView.swift
//  metere
//

import SwiftUI

public struct UpdateSheetView: View {
    @ObservedObject var updateManager: UpdateManager
    @Environment(\.dismiss) private var dismiss

    public init(updateManager: UpdateManager = .shared) {
        self.updateManager = updateManager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Section
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // Content / Release Notes
            contentView
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            // Footer Action Buttons
            footerView
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
        }
        .frame(width: 520, height: 460)
    }

    // MARK: - Header
    @ViewBuilder
    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)

                Image(systemName: "waveform.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let update = updateManager.availableUpdate {
                    Text("A new version of Metere is available!")
                        .font(.system(size: 15, weight: .semibold))

                    HStack(spacing: 6) {
                        Text("Metere \(update.version.description)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text("You have v\(SemanticVersion.currentAppVersion.description)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        if update.isPrerelease {
                            Text("Pre-release")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                        }
                    }

                    Text("Published on \(update.publishedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("Software Update")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Checking for the latest releases…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Content
    @ViewBuilder
    private var contentView: some View {
        if let update = updateManager.availableUpdate {
            VStack(alignment: .leading, spacing: 12) {
                Text("Release Notes")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !update.releaseTitle.isEmpty && update.releaseTitle != "Metere \(update.version.description)" {
                            Text(update.releaseTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.bottom, 2)
                        }

                        Text(update.releaseNotes)
                            .font(.system(size: 12))
                            .foregroundColor(.primary.opacity(0.9))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Download Progress / Status Bar
                if case .downloading(let progress, let bytesWritten, let totalBytes) = updateManager.status {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Downloading update…")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            if totalBytes > 0 {
                                let writtenMB = Double(bytesWritten) / 1_048_576.0
                                let totalMB = Double(totalBytes) / 1_048_576.0
                                Text(String(format: "%.1f / %.1f MB (%.0f%%)", writtenMB, totalMB, progress * 100))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(Double(bytesWritten) / 1_048_576.0, specifier: "%.1f") MB")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }

                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    }
                    .padding(.top, 4)
                } else if case .downloaded(_, _) = updateManager.status {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Update downloaded successfully and ready for installation.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 4)
                } else if case .error(let message) = updateManager.status {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .padding(.top, 4)
                }
            }
        } else {
            VStack {
                Spacer()
                ProgressView()
                    .scaleEffect(0.9)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Footer
    @ViewBuilder
    private var footerView: some View {
        HStack(spacing: 10) {
            if let update = updateManager.availableUpdate {
                Button("Skip This Version") {
                    updateManager.skipVersion(update.rawTagName)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

                Button("View on GitHub") {
                    updateManager.openReleasePage(update)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .padding(.leading, 8)
            }

            Spacer()

            switch updateManager.status {
            case .downloading:
                Button("Cancel") {
                    updateManager.cancelDownload()
                }
                .keyboardShortcut(.cancelAction)

            case .downloaded:
                Button("Later") {
                    dismiss()
                }

                Button("Install & Relaunch") {
                    updateManager.installDownloadedUpdate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

            default:
                Button("Remind Me Later") {
                    updateManager.remindLater()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if let update = updateManager.availableUpdate {
                    Button(update.downloadURL != nil ? "Download and Install" : "Open in Browser") {
                        if update.downloadURL != nil {
                            updateManager.downloadUpdate(update)
                        } else {
                            updateManager.openReleasePage(update)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
