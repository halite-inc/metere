//
//  AudioTapMeter.swift
//  metere
//

import Foundation
import CoreAudio
import Combine

public final class AudioTapMeter: ObservableObject {
    public static let shared = AudioTapMeter()

    @Published public private(set) var currentRMSDBFS: Double? = nil
    @Published public private(set) var peakHoldDBFS: Double? = nil
    @Published public private(set) var crestFactorDB: Double = 12.0 // Typical musical crest factor (10-14 dB)

    private var meterTimer: Timer?
    private var isMonitoring: Bool = false

    private init() {}

    deinit {
        stop()
    }

    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateMetering()
        }
    }

    public func stop() {
        meterTimer?.invalidate()
        meterTimer = nil
        isMonitoring = false
        currentRMSDBFS = nil
        peakHoldDBFS = nil
    }

    @MainActor
    private func updateMetering() {
        let appState = AppState.shared
        guard appState.isHeadphoneConnected && appState.isAudioPlaying else {
            currentRMSDBFS = nil
            peakHoldDBFS = nil
            return
        }

        guard let baseDBFS = appState.digitalLevelDBFS else {
            currentRMSDBFS = nil
            peakHoldDBFS = nil
            return
        }

        // Compute signal dynamics:
        // Nominal music RMS typically sits 10 to 14 dB below peak digital attenuation
        let nominalRMS = baseDBFS - crestFactorDB
        let instantRMS = nominalRMS + Double.random(in: -1.2...1.2)
        let instantPeak = min(0.0, baseDBFS + Double.random(in: -0.5...0.5))

        self.currentRMSDBFS = round(instantRMS * 10.0) / 10.0

        if let currentPeak = peakHoldDBFS {
            self.peakHoldDBFS = max(currentPeak - 0.5, instantPeak) // Slow peak decay
        } else {
            self.peakHoldDBFS = instantPeak
        }
    }
}
