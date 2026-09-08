//
//  BluetoothDeviceManager.swift
//  metere
//

import Foundation
import CoreAudio

public protocol BluetoothDeviceManagerDelegate: AnyObject {
    func activeHeadphoneDidChange(to device: AudioDevice?)
    func defaultOutputDeviceDidChange(to device: AudioDevice?)
    func deviceVolumeDidChange(volume: Float)
    func audioPlaybackStateDidChange(isPlaying: Bool)
}

public final class BluetoothDeviceManager {
    public weak var delegate: BluetoothDeviceManagerDelegate?

    private let audioBridge: CoreAudioBridge
    public private(set) var currentDefaultDevice: AudioDevice?
    public private(set) var activeHeadphone: AudioDevice?
    public private(set) var connectedHeadphones: [AudioDevice] = []
    public private(set) var isAudioPlaying: Bool = false

    public init(audioBridge: CoreAudioBridge = .shared) {
        self.audioBridge = audioBridge
    }

    public func start() {
        setupCallbacks()
        audioBridge.startMonitoringHardware()
        refresh()
    }

    public func stop() {
        audioBridge.stopMonitoringHardware()
        audioBridge.stopMonitoringDevice()
    }

    public func refresh() {
        let defaultID = audioBridge.getDefaultOutputDeviceID()
        handleDefaultDeviceChanged(to: defaultID)
        refreshConnectedHeadphones()
    }

    private func setupCallbacks() {
        audioBridge.onDefaultDeviceChanged = { [weak self] newDeviceID in
            DispatchQueue.main.async {
                self?.handleDefaultDeviceChanged(to: newDeviceID)
            }
        }

        audioBridge.onDevicesListChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }

        audioBridge.onVolumeChanged = { [weak self] newVolume in
            DispatchQueue.main.async {
                self?.delegate?.deviceVolumeDidChange(volume: newVolume)
            }
        }

        audioBridge.onPlaybackStateChanged = { [weak self] isPlaying in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isAudioPlaying = isPlaying
                self.delegate?.audioPlaybackStateDidChange(isPlaying: isPlaying)
            }
        }
    }

    private func handleDefaultDeviceChanged(to deviceID: AudioDeviceID) {
        guard let device = audioBridge.getAudioDevice(for: deviceID) else {
            if activeHeadphone != nil {
                activeHeadphone = nil
                isAudioPlaying = false
                audioBridge.stopMonitoringDevice()
                delegate?.activeHeadphoneDidChange(to: nil)
                delegate?.audioPlaybackStateDidChange(isPlaying: false)
            }
            currentDefaultDevice = nil
            delegate?.defaultOutputDeviceDidChange(to: nil)
            return
        }

        currentDefaultDevice = device
        delegate?.defaultOutputDeviceDidChange(to: device)

        if device.isBluetoothHeadphone {
            let deviceChanged = activeHeadphone?.id != device.id
            if deviceChanged {
                activeHeadphone = device
                audioBridge.monitorDevice(device.id)
                delegate?.activeHeadphoneDidChange(to: device)
            }
            // Check immediate playback state
            let currentlyPlaying = audioBridge.isAudioActivelyPlaying(for: device.id)
            if currentlyPlaying != isAudioPlaying || deviceChanged {
                isAudioPlaying = currentlyPlaying
                delegate?.audioPlaybackStateDidChange(isPlaying: currentlyPlaying)
            }
        } else {
            if activeHeadphone != nil {
                activeHeadphone = nil
                isAudioPlaying = false
                audioBridge.stopMonitoringDevice()
                delegate?.activeHeadphoneDidChange(to: nil)
                delegate?.audioPlaybackStateDidChange(isPlaying: false)
            }
        }
    }

    private func refreshConnectedHeadphones() {
        let allIDs = audioBridge.getAllDeviceIDs()
        var headphones: [AudioDevice] = []
        for id in allIDs {
            if let dev = audioBridge.getAudioDevice(for: id), dev.isBluetoothHeadphone {
                headphones.append(dev)
            }
        }
        self.connectedHeadphones = headphones
    }
}
