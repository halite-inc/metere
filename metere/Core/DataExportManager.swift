//
//  DataExportManager.swift
//  metere
//

import Foundation
import AppKit

public final class DataExportManager {
    public static let shared = DataExportManager()

    private init() {}

    /// Generates standard RFC-4180 CSV representation of listening history
    public func generateCSV(from sessions: [ListeningSession]) -> String {
        var csv = "Session ID,Start Time,End Time,Duration (Seconds),Duration Formatted,Device Name,Device UID,Average dBFS,Peak dBFS,Average Volume,Source App\n"

        let dateFormatter = ISO8601DateFormatter()

        for s in sessions {
            let idStr = s.id.uuidString
            let startStr = dateFormatter.string(from: s.startTime)
            let endStr = s.endTime.map { dateFormatter.string(from: $0) } ?? "Active"
            let durSec = String(format: "%.1f", s.activePlaybackDuration)
            let durFmt = DailyStatistics.formattedDuration(s.activePlaybackDuration)
            let devName = escapeCSV(s.deviceName)
            let devUID = escapeCSV(s.deviceUID)
            let avgDBFS = s.averageDBFS.map { String(format: "%.1f", $0) } ?? ""
            let peakDBFS = s.maxDBFS.map { String(format: "%.1f", $0) } ?? ""
            let avgVol = s.averageVolume.map { "\(Int(round($0 * 100)))%" } ?? ""
            let source = escapeCSV(s.sourceApp)

            let row = "\(idStr),\(startStr),\(endStr),\(durSec),\"\(durFmt)\",\(devName),\(devUID),\(avgDBFS),\(peakDBFS),\(avgVol),\(source)\n"
            csv.append(row)
        }

        return csv
    }

    /// Generates structured JSON representation of listening history
    public func generateJSON(from data: PersistedData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }

    /// Presents a native macOS NSSavePanel to export text or data to user's local disk
    @MainActor
    public func presentSavePanel(
        defaultFilename: String,
        content: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.nameFieldStringValue = defaultFilename
        savePanel.isExtensionHidden = false

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                completion?(false)
                return
            }

            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                completion?(true)
            } catch {
                print("[DataExportManager] Error exporting file: \(error.localizedDescription)")
                completion?(false)
            }
        }
    }

    /// Presents a native macOS NSSavePanel to export binary Data to user's local disk
    @MainActor
    public func presentSavePanel(
        defaultFilename: String,
        data: Data,
        completion: ((Bool) -> Void)? = nil
    ) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.nameFieldStringValue = defaultFilename
        savePanel.isExtensionHidden = false

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                completion?(false)
                return
            }

            do {
                try data.write(to: url)
                completion?(true)
            } catch {
                print("[DataExportManager] Error exporting data: \(error.localizedDescription)")
                completion?(false)
            }
        }
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
