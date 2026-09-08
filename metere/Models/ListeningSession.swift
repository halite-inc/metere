//
//  ListeningSession.swift
//  metere
//

import Foundation

public struct ListeningSession: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let deviceUID: String
    public let deviceName: String
    public let startTime: Date
    public var endTime: Date?
    public var lastHeartbeat: Date

    /// Total seconds during this session that audio was actively playing
    public var activePlaybackDuration: TimeInterval

    /// Timestamp when current active playback interval started (nil if paused/idle)
    public var currentPlaybackStart: Date?

    public var sampleCount: Int
    public var sumDBFS: Double
    public var minDBFS: Double?
    public var maxDBFS: Double?
    public var sumVolume: Float
    public var sampleVolumeCount: Int
    public var sourceApp: String
    public var calibratedPlaybackDuration: TimeInterval
    public var appDurations: [String: TimeInterval]

    public init(
        id: UUID = UUID(),
        deviceUID: String,
        deviceName: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        lastHeartbeat: Date = Date(),
        activePlaybackDuration: TimeInterval = 0,
        currentPlaybackStart: Date? = nil,
        sampleCount: Int = 0,
        sumDBFS: Double = 0,
        minDBFS: Double? = nil,
        maxDBFS: Double? = nil,
        sumVolume: Float = 0,
        sampleVolumeCount: Int = 0,
        sourceApp: String = "Unknown source",
        calibratedPlaybackDuration: TimeInterval = 0,
        appDurations: [String: TimeInterval] = [:]
    ) {
        self.id = id
        self.deviceUID = deviceUID
        self.deviceName = deviceName
        self.startTime = startTime
        self.endTime = endTime
        self.lastHeartbeat = lastHeartbeat
        self.activePlaybackDuration = activePlaybackDuration
        self.currentPlaybackStart = currentPlaybackStart
        self.sampleCount = sampleCount
        self.sumDBFS = sumDBFS
        self.minDBFS = minDBFS
        self.maxDBFS = maxDBFS
        self.sumVolume = sumVolume
        self.sampleVolumeCount = sampleVolumeCount
        self.sourceApp = sourceApp
        self.calibratedPlaybackDuration = calibratedPlaybackDuration
        self.appDurations = appDurations
    }

    private enum CodingKeys: String, CodingKey {
        case id, deviceUID, deviceName, startTime, endTime, lastHeartbeat
        case activePlaybackDuration, currentPlaybackStart, sampleCount, sumDBFS, minDBFS, maxDBFS
        case sumVolume, sampleVolumeCount, sourceApp, calibratedPlaybackDuration, appDurations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.deviceUID = try container.decode(String.self, forKey: .deviceUID)
        self.deviceName = try container.decode(String.self, forKey: .deviceName)
        self.startTime = try container.decode(Date.self, forKey: .startTime)
        self.endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        self.lastHeartbeat = try container.decodeIfPresent(Date.self, forKey: .lastHeartbeat) ?? self.startTime
        self.activePlaybackDuration = try container.decode(TimeInterval.self, forKey: .activePlaybackDuration)
        self.currentPlaybackStart = try container.decodeIfPresent(Date.self, forKey: .currentPlaybackStart)
        self.sampleCount = try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
        self.sumDBFS = try container.decodeIfPresent(Double.self, forKey: .sumDBFS) ?? 0
        self.minDBFS = try container.decodeIfPresent(Double.self, forKey: .minDBFS)
        self.maxDBFS = try container.decodeIfPresent(Double.self, forKey: .maxDBFS)
        self.sumVolume = try container.decodeIfPresent(Float.self, forKey: .sumVolume) ?? 0
        self.sampleVolumeCount = try container.decodeIfPresent(Int.self, forKey: .sampleVolumeCount) ?? 0
        self.sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp) ?? "Unknown source"
        self.calibratedPlaybackDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .calibratedPlaybackDuration) ?? 0
        self.appDurations = try container.decodeIfPresent([String: TimeInterval].self, forKey: .appDurations) ?? [:]
    }

    public var uncalibratedPlaybackDuration: TimeInterval {
        max(0, activePlaybackDuration - calibratedPlaybackDuration)
    }

    public mutating func recordCalibratedInterval(_ seconds: TimeInterval) {
        calibratedPlaybackDuration += seconds
    }

    public mutating func recordAppDuration(app: String, seconds: TimeInterval) {
        let clean = app.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        self.appDurations[clean, default: 0] += seconds
        self.sourceApp = clean
    }

    public var isActive: Bool {
        endTime == nil
    }

    public var isAudioPlaying: Bool {
        currentPlaybackStart != nil
    }

    /// Calculated active listening duration in seconds (strictly during playback)
    public func duration(at referenceDate: Date = Date()) -> TimeInterval {
        var total = activePlaybackDuration
        if let start = currentPlaybackStart {
            let currentInterval = max(0, referenceDate.timeIntervalSince(start))
            total += currentInterval
        }
        return total
    }

    /// Average digital level (dBFS) during playback for this session
    public var averageDBFS: Double? {
        guard sampleCount > 0 else { return nil }
        return sumDBFS / Double(sampleCount)
    }

    /// Average system volume scalar (0...1) during playback for this session
    public var averageVolume: Float? {
        guard sampleVolumeCount > 0 else { return nil }
        return sumVolume / Float(sampleVolumeCount)
    }

    /// Marks audio playback started
    public mutating func startPlayback(at timestamp: Date = Date()) {
        guard currentPlaybackStart == nil else { return }
        currentPlaybackStart = timestamp
        lastHeartbeat = timestamp
    }

    /// Marks audio playback paused/stopped
    public mutating func pausePlayback(at timestamp: Date = Date()) {
        guard let start = currentPlaybackStart else { return }
        let interval = max(0, timestamp.timeIntervalSince(start))
        activePlaybackDuration += interval
        currentPlaybackStart = nil
        lastHeartbeat = timestamp
    }

    /// Records a new measurable digital attenuation sample and volume scalar during playback
    public mutating func recordSample(_ dbfs: Double, volume: Float? = nil, at timestamp: Date = Date()) {
        sampleCount += 1
        sumDBFS += dbfs
        if let currentMin = minDBFS {
            minDBFS = min(currentMin, dbfs)
        } else {
            minDBFS = dbfs
        }
        if let currentMax = maxDBFS {
            maxDBFS = max(currentMax, dbfs)
        } else {
            maxDBFS = dbfs
        }

        if let v = volume {
            sumVolume += v
            sampleVolumeCount += 1
        }
        lastHeartbeat = timestamp
    }

    /// Finalizes the session when headphones disconnect or output route changes
    public mutating func complete(at endTimestamp: Date = Date()) {
        pausePlayback(at: endTimestamp)
        self.endTime = max(startTime, endTimestamp)
        self.lastHeartbeat = self.endTime!
    }
}
