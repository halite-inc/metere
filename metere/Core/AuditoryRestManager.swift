//
//  AuditoryRestManager.swift
//  metere
//

import Foundation
import SwiftUI
import Combine

@MainActor
public final class AuditoryRestManager: ObservableObject {
    public static let shared = AuditoryRestManager()

    @Published public private(set) var isRecoveryRecommended: Bool = false
    @Published public private(set) var recommendedRestSeconds: TimeInterval = 0
    @Published public private(set) var elapsedRestSeconds: TimeInterval = 0
    @Published public private(set) var lastSessionDuration: TimeInterval = 0
    @Published public private(set) var lastSessionVolume: Float = 0.50
    @Published public private(set) var isResting: Bool = false

    private var restTimer: Timer?
    private var restStartTime: Date?

    public init() {}

    deinit {
        restTimer?.invalidate()
    }

    /// Computes recommended quiet recovery duration based on continuous playback time and average system volume
    nonisolated public static func calculateRecommendedRest(duration: TimeInterval, volume: Float) -> TimeInterval {
        guard duration >= 1500 else { return 0 } // Minimum 25 minutes before formal rest recommendation

        let factor: Double
        if volume > 0.75 {
            factor = 0.40 // 40% of duration for high volume
        } else if volume > 0.50 {
            factor = 0.25 // 25% of duration for moderate-high volume
        } else {
            factor = 0.15 // 15% of duration for normal volume
        }

        return max(180, duration * factor) // Minimum 3 minutes if recommended
    }

    /// Called when playback pauses or stops after an active interval
    public func handlePlaybackPaused(continuousDuration: TimeInterval, averageVolume: Float) {
        let recommended = Self.calculateRecommendedRest(duration: continuousDuration, volume: averageVolume)
        self.lastSessionDuration = continuousDuration
        self.lastSessionVolume = averageVolume
        self.recommendedRestSeconds = recommended

        if recommended > 0 {
            self.isRecoveryRecommended = true
            self.isResting = true
            self.elapsedRestSeconds = 0
            self.restStartTime = Date()
            startRestTimer()
        } else {
            self.isRecoveryRecommended = false
            self.isResting = false
            stopRestTimer()
        }
    }

    /// Called when playback resumes
    public func handlePlaybackResumed() {
        if isResting {
            // Interrupted rest
            self.isResting = false
            stopRestTimer()
        }
    }

    private func startRestTimer() {
        stopRestTimer()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickRest()
            }
        }
    }

    private func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
    }

    private func tickRest() {
        guard let start = restStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        self.elapsedRestSeconds = elapsed

        if elapsed >= recommendedRestSeconds {
            self.isResting = false
            self.isRecoveryRecommended = false
            stopRestTimer()
        }
    }

    public var remainingRestSeconds: TimeInterval {
        max(0, recommendedRestSeconds - elapsedRestSeconds)
    }

    public var formattedRecommendedRest: String {
        DailyStatistics.formattedDuration(recommendedRestSeconds)
    }

    public var formattedRemainingRest: String {
        DailyStatistics.formattedDuration(remainingRestSeconds)
    }

    public var formattedElapsedRest: String {
        DailyStatistics.formattedDuration(elapsedRestSeconds)
    }

    public var recoveryProgress: Double {
        guard recommendedRestSeconds > 0 else { return 1.0 }
        return min(1.0, elapsedRestSeconds / recommendedRestSeconds)
    }

    public var statusDescription: String {
        if isResting {
            return "Quiet rest in progress: \(formattedRemainingRest) remaining"
        } else if recommendedRestSeconds > 0 && elapsedRestSeconds >= recommendedRestSeconds {
            return "Auditory rest complete — Ear fatigue recovered"
        } else if recommendedRestSeconds > 0 {
            return "Rest paused (\(formattedRemainingRest) remaining recommended)"
        } else {
            return "No recovery required (Playback under 25m threshold)"
        }
    }
}
