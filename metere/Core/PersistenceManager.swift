//
//  PersistenceManager.swift
//  metere
//

import Foundation

public struct PersistedData: Codable, Sendable {
    public var dailyRecords: [String: DailyStatistics] // keyed by "yyyy-MM-dd"
    public var activeSession: ListeningSession?
    public var lastSavedTimestamp: Date

    public init(
        dailyRecords: [String: DailyStatistics] = [:],
        activeSession: ListeningSession? = nil,
        lastSavedTimestamp: Date = Date()
    ) {
        self.dailyRecords = dailyRecords
        self.activeSession = activeSession
        self.lastSavedTimestamp = lastSavedTimestamp
    }
}

public final class PersistenceManager: @unchecked Sendable {
    public static let shared = PersistenceManager()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.halite.metere.persistence", qos: .utility)
    private let storageURL: URL

    public init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = appSupport.appendingPathComponent("com.halite.metere", isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        self.storageURL = directoryURL.appendingPathComponent("exposure_data.json")
    }

    /// Loads persisted data, creating a fresh default container if no file exists.
    public func loadData() -> PersistedData {
        guard fileManager.fileExists(atPath: storageURL.path),
              let rawData = try? Data(contentsOf: storageURL) else {
            return PersistedData()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(PersistedData.self, from: rawData)
        } catch {
            print("[PersistenceManager] Failed to decode existing data, starting fresh: \(error)")
            return PersistedData()
        }
    }

    /// Asynchronously saves data with atomic file write
    public func saveData(_ data: PersistedData, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let success = self.writeSync(data: data)
            completion?(success)
        }
    }

    /// Synchronous save for app termination / sleep handling
    public func saveSync(_ data: PersistedData) -> Bool {
        var result = false
        queue.sync {
            result = self.writeSync(data: data)
        }
        return result
    }

    private func writeSync(data: PersistedData) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Prune records older than 30 days to optimize storage
        var prunedData = data
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        prunedData.dailyRecords = prunedData.dailyRecords.filter { _, stats in
            stats.calendarDate >= thirtyDaysAgo
        }

        do {
            let encoded = try encoder.encode(prunedData)
            try encoded.write(to: self.storageURL, options: [.atomicWrite])
            return true
        } catch {
            print("[PersistenceManager] Failed to write data: \(error)")
            return false
        }
    }

    /// Clear all data
    public func clearAll() {
        queue.sync {
            let fresh = PersistedData()
            _ = self.writeSync(data: fresh)
        }
    }
}
