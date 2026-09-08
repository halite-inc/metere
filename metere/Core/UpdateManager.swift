//
//  UpdateManager.swift
//  metere
//

import Foundation
import SwiftUI
import Combine
import UserNotifications

/// Manages release checking, notification, asset downloading, and update presentation for Metere.
@MainActor
public final class UpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = UpdateManager()

    public enum UpdateStatus: Equatable, Sendable {
        case idle
        case checking
        case upToDate(checkedAt: Date)
        case available(AppUpdateInfo)
        case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
        case downloaded(fileURL: URL, updateInfo: AppUpdateInfo)
        case installing
        case error(String)
    }

    @Published public private(set) var status: UpdateStatus = .idle
    @Published public private(set) var lastCheckDate: Date? = nil
    @Published public var showingUpdateSheet: Bool = false

    public var hasUpdateAvailable: Bool {
        switch status {
        case .available, .downloading, .downloaded:
            return true
        default:
            return false
        }
    }

    public var availableUpdate: AppUpdateInfo? {
        switch status {
        case .available(let info):
            return info
        case .downloading(_, _, _):
            return activeDownloadingUpdate
        case .downloaded(_, let info):
            return info
        default:
            return nil
        }
    }

    private let settings: AppSettings
    private var downloadSession: URLSession?
    private var currentDownloadTask: URLSessionDownloadTask?
    private var activeDownloadingUpdate: AppUpdateInfo?
    private var backgroundTimer: Timer?

    public init(settings: AppSettings = .shared) {
        self.settings = settings
        self.lastCheckDate = settings.lastUpdateCheckDate
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        self.downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    deinit {
        backgroundTimer?.invalidate()
    }

    // MARK: - Update Check Workflow

    /// Queries the update feed (GitHub Releases) for newer versions.
    public func checkForUpdates(userInitiated: Bool = false) {
        guard status != .checking else { return }
        status = .checking

        let repo = settings.updateRepository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty, repo.contains("/") else {
            self.status = .error("Invalid repository format. Expected 'owner/repo'.")
            return
        }

        let urlString = "https://api.github.com/repos/\(repo)/releases"
        guard let url = URL(string: urlString) else {
            self.status = .error("Invalid update feed URL.")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Metere-App/\(SemanticVersion.currentAppVersion.description) (macOS)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.status = .error("Invalid server response.")
                    return
                }

                if httpResponse.statusCode == 404 {
                    self.status = .error("Repository '\(repo)' or its releases were not found.")
                    return
                } else if httpResponse.statusCode == 403 {
                    self.status = .error("GitHub API rate limit exceeded. Please try again later.")
                    return
                } else if httpResponse.statusCode != 200 {
                    self.status = .error("Update check failed with HTTP status \(httpResponse.statusCode).")
                    return
                }

                let decoder = JSONDecoder()
                let releases = try decoder.decode([GitHubReleasePayload].self, from: data)

                self.evaluateReleases(releases, userInitiated: userInitiated)

            } catch {
                let errDesc = error.localizedDescription
                self.status = .error("Unable to check for updates: \(errDesc)")
            }
        }
    }

    /// Evaluates list of releases against current version and user preferences.
    public func evaluateReleases(_ releases: [GitHubReleasePayload], userInitiated: Bool) {
        let now = Date()
        self.lastCheckDate = now
        self.settings.lastUpdateCheckDate = now

        let includePrerelease = settings.includePrereleases
        let currentVersion = SemanticVersion.currentAppVersion

        // Filter valid releases
        let validUpdates = releases.compactMap { AppUpdateInfo.parse(from: $0) }
            .filter { update in
                if !includePrerelease && update.isPrerelease {
                    return false
                }
                return update.version > currentVersion
            }
            .sorted(by: { $0.version > $1.version })

        guard let newest = validUpdates.first else {
            self.status = .upToDate(checkedAt: now)
            return
        }

        // Check if user chose to skip this specific release during automatic checks
        if !userInitiated, let skipped = settings.skippedVersion, skipped == newest.rawTagName {
            self.status = .upToDate(checkedAt: now)
            return
        }

        self.status = .available(newest)

        if userInitiated {
            self.showingUpdateSheet = true
        } else {
            postBackgroundUpdateNotification(for: newest)
        }
    }

    // MARK: - Background Scheduling

    public func startScheduledChecks() {
        guard settings.automaticallyCheckForUpdates else { return }

        let interval = settings.updateCheckInterval
        let now = Date()

        let shouldCheckImmediately: Bool
        if let last = settings.lastUpdateCheckDate {
            shouldCheckImmediately = (now.timeIntervalSince(last) >= interval)
        } else {
            shouldCheckImmediately = true
        }

        if shouldCheckImmediately {
            // Wait 6 seconds after app boot so audio bridges and UI initialize smoothly
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                self?.checkForUpdates(userInitiated: false)
            }
        }

        // Schedule timer if interval > 0
        if interval > 0 {
            backgroundTimer?.invalidate()
            backgroundTimer = Timer.scheduledTimer(withTimeInterval: max(interval, 3600.0), repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.settings.automaticallyCheckForUpdates else { return }
                    self.checkForUpdates(userInitiated: false)
                }
            }
        }
    }

    private func postBackgroundUpdateNotification(for update: AppUpdateInfo) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Metere Update Available"
        content.subtitle = "Version \(update.version.description) is now available"
        content.body = "Click to view release notes and install the latest features & improvements."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.halite.metere.update.\(update.rawTagName)",
            content: content,
            trigger: nil // immediate delivery
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[UpdateManager] Failed to post update notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Skip & Remind

    public func skipVersion(_ versionString: String) {
        settings.skippedVersion = versionString
        status = .upToDate(checkedAt: Date())
        showingUpdateSheet = false
    }

    public func remindLater() {
        showingUpdateSheet = false
    }

    // MARK: - Download & Installation

    public func downloadUpdate(_ update: AppUpdateInfo) {
        guard let downloadURL = update.downloadURL else {
            // Fallback: Open browser if direct binary asset is not attached to release
            openReleasePage(update)
            return
        }

        currentDownloadTask?.cancel()
        activeDownloadingUpdate = update
        status = .downloading(progress: 0.0, bytesWritten: 0, totalBytes: update.assetSize ?? 0)

        var request = URLRequest(url: downloadURL)
        request.setValue("Metere-App/\(SemanticVersion.currentAppVersion.description) (macOS)", forHTTPHeaderField: "User-Agent")

        let task = downloadSession?.downloadTask(with: request)
        currentDownloadTask = task
        task?.resume()
    }

    public func cancelDownload() {
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        if let update = activeDownloadingUpdate {
            status = .available(update)
        } else {
            status = .idle
        }
    }

    public func installDownloadedUpdate() {
        guard case .downloaded(let fileURL, _) = status else { return }

        status = .installing

        let ext = fileURL.pathExtension.lowercased()
        if ext == "dmg" {
            // Mount DMG and present in Finder
            NSWorkspace.shared.open(fileURL)
        } else if ext == "zip" {
            // Reveal in Finder so user can extract or replace
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.open(fileURL)
        }
    }

    public func openReleasePage(_ update: AppUpdateInfo) {
        NSWorkspace.shared.open(update.htmlURL)
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (self.activeDownloadingUpdate?.assetSize ?? 0)
            let progress = expected > 0 ? Double(totalBytesWritten) / Double(expected) : 0.0

            self.status = .downloading(
                progress: min(max(progress, 0.0), 1.0),
                bytesWritten: totalBytesWritten,
                totalBytes: expected
            )
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let tempDestination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + location.lastPathComponent)
        try? FileManager.default.copyItem(at: location, to: tempDestination)

        Task { @MainActor in
            guard let update = self.activeDownloadingUpdate else { return }

            let fileName = update.assetName ?? "MetereUpdate.\(location.pathExtension.isEmpty ? "dmg" : location.pathExtension)"
            let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let destinationURL = downloadsDir.appendingPathComponent(fileName)

            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempDestination, to: destinationURL)
                self.status = .downloaded(fileURL: destinationURL, updateInfo: update)
            } catch {
                self.status = .error("Failed to save downloaded update: \(error.localizedDescription)")
            }
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error as? URLError, error.code == .cancelled {
            return
        }

        Task { @MainActor in
            if let error = error {
                self.status = .error("Download failed: \(error.localizedDescription)")
            }
        }
    }
}
