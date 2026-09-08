//
//  CoreAudioBridge.swift
//  metere
//

import Foundation
import CoreAudio
import AudioToolbox

public final class CoreAudioBridge {
    public static let shared = CoreAudioBridge()

    public typealias DeviceChangeHandler = @Sendable (AudioDeviceID) -> Void
    public typealias VolumeChangeHandler = @Sendable (Float) -> Void
    public typealias PlaybackChangeHandler = @Sendable (Bool) -> Void
    public typealias DevicesListChangeHandler = @Sendable () -> Void

    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var devicesListListenerBlock: AudioObjectPropertyListenerBlock?

    private var monitoredDeviceID: AudioDeviceID?
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var isRunningListenerBlock: AudioObjectPropertyListenerBlock?

    public var onDefaultDeviceChanged: DeviceChangeHandler?
    public var onVolumeChanged: VolumeChangeHandler?
    public var onPlaybackStateChanged: PlaybackChangeHandler?
    public var onDevicesListChanged: DevicesListChangeHandler?

    private init() {}

    deinit {
        stopMonitoringHardware()
        stopMonitoringDevice()
    }

    // MARK: - Hardware Level Monitoring

    public func startMonitoringHardware() {
        stopMonitoringHardware()

        // 1. Listen for default output device changes
        var defaultOutputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let devBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            let newID = self.getDefaultOutputDeviceID()
            self.onDefaultDeviceChanged?(newID)
        }
        self.defaultDeviceListenerBlock = devBlock

        let status1 = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddr,
            DispatchQueue.main,
            devBlock
        )
        if status1 != noErr {
            print("[CoreAudioBridge] Failed to add default device listener: \(status1)")
        }

        // 2. Listen for device list additions/removals
        var devicesListAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            self.onDevicesListChanged?()
        }
        self.devicesListListenerBlock = listBlock

        let status2 = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesListAddr,
            DispatchQueue.main,
            listBlock
        )
        if status2 != noErr {
            print("[CoreAudioBridge] Failed to add devices list listener: \(status2)")
        }
    }

    public func stopMonitoringHardware() {
        if let block = defaultDeviceListenerBlock {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
            defaultDeviceListenerBlock = nil
        }

        if let block = devicesListListenerBlock {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
            devicesListListenerBlock = nil
        }
    }

    // MARK: - Active Device Volume & State Monitoring

    public func monitorDevice(_ deviceID: AudioDeviceID) {
        if monitoredDeviceID == deviceID {
            return
        }
        stopMonitoringDevice()
        monitoredDeviceID = deviceID

        // 1. Monitor Virtual Main Volume
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            let vol = self.getVolume(for: deviceID)
            self.onVolumeChanged?(vol)
        }
        self.volumeListenerBlock = volBlock

        let volStatus = AudioObjectAddPropertyListenerBlock(deviceID, &volAddr, DispatchQueue.main, volBlock)
        if volStatus != noErr {
            // Try scalar volume as fallback
            var scalarAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(deviceID, &scalarAddr, DispatchQueue.main, volBlock)
        }

        // 2. Monitor Mute State
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            let vol = self.getVolume(for: deviceID)
            self.onVolumeChanged?(vol)
        }
        self.muteListenerBlock = muteBlock
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddr, DispatchQueue.main, muteBlock)

        // 3. Monitor isRunningSomewhere for Playback Start/Stop
        var runAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let runBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            let isPlaying = self.isAudioActivelyPlaying(for: deviceID)
            self.onPlaybackStateChanged?(isPlaying)
        }
        self.isRunningListenerBlock = runBlock
        AudioObjectAddPropertyListenerBlock(deviceID, &runAddr, DispatchQueue.main, runBlock)
    }

    public func stopMonitoringDevice() {
        guard let deviceID = monitoredDeviceID else { return }

        if let block = volumeListenerBlock {
            var volAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &volAddr, DispatchQueue.main, block)
            var scalarAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &scalarAddr, DispatchQueue.main, block)
            volumeListenerBlock = nil
        }

        if let block = muteListenerBlock {
            var muteAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddr, DispatchQueue.main, block)
            muteListenerBlock = nil
        }

        if let block = isRunningListenerBlock {
            var runAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &runAddr, DispatchQueue.main, block)
            isRunningListenerBlock = nil
        }

        monitoredDeviceID = nil
    }

    // MARK: - Core Audio Property Queries

    public func getDefaultOutputDeviceID() -> AudioDeviceID {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &defaultOutputDeviceID
        )

        if status != noErr {
            print("[CoreAudioBridge] Failed to get default output device ID: \(status)")
        }
        return defaultOutputDeviceID
    }

    public func getAllDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return [] }
        return deviceIDs
    }

    public func getAudioDevice(for deviceID: AudioDeviceID) -> AudioDevice? {
        guard deviceID != 0 else { return nil }

        let name = getStringProperty(deviceID, kAudioDevicePropertyDeviceNameCFString) ?? "Unknown Device"
        let uid = getStringProperty(deviceID, kAudioDevicePropertyDeviceUID) ?? "\(deviceID)"
        let modelUID = getStringProperty(deviceID, kAudioDevicePropertyModelUID)
        let manufacturer = getStringProperty(deviceID, kAudioObjectPropertyManufacturer)
        let rawTransport = getUInt32Property(deviceID, kAudioDevicePropertyTransportType) ?? 0
        let transport = AudioTransportType.from(rawType: rawTransport)

        // Check if device has output streams
        var streamsAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamSize: UInt32 = 0
        let streamStatus = AudioObjectGetPropertyDataSize(deviceID, &streamsAddr, 0, nil, &streamSize)
        let hasOutput = streamStatus == noErr && streamSize > 0

        return AudioDevice(
            id: deviceID,
            uid: uid,
            name: name,
            manufacturer: manufacturer,
            modelUID: modelUID,
            transportType: transport,
            hasOutput: hasOutput
        )
    }

    public func getVolume(for deviceID: AudioDeviceID) -> Float {
        // If device is muted, return 0.0
        if isMuted(for: deviceID) {
            return 0.0
        }

        // Try VirtualMainVolume first (preferred for Bluetooth headphones)
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float32 = 0.0
        var size = UInt32(MemoryLayout<Float32>.size)
        var status = AudioObjectGetPropertyData(deviceID, &volAddr, 0, nil, &size, &volume)

        if status == noErr {
            return min(max(volume, 0.0), 1.0)
        }

        // Fallback: master channel VolumeScalar
        var scalarAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        status = AudioObjectGetPropertyData(deviceID, &scalarAddr, 0, nil, &size, &volume)
        if status == noErr {
            return min(max(volume, 0.0), 1.0)
        }

        // Fallback: Channel 1
        scalarAddr.mElement = 1
        status = AudioObjectGetPropertyData(deviceID, &scalarAddr, 0, nil, &size, &volume)
        if status == noErr {
            return min(max(volume, 0.0), 1.0)
        }

        return 0.0
    }

    /// Sets output volume scalar (0.0 ... 1.0) for the specified device
    public func setVolume(_ volume: Float, for deviceID: AudioDeviceID) {
        guard deviceID != 0 else { return }
        var vol: Float32 = min(max(volume, 0.0), 1.0)
        let size = UInt32(MemoryLayout<Float32>.size)

        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(deviceID, &volAddr) {
            AudioObjectSetPropertyData(deviceID, &volAddr, 0, nil, size, &vol)
        } else {
            var scalarAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(deviceID, &scalarAddr) {
                AudioObjectSetPropertyData(deviceID, &scalarAddr, 0, nil, size, &vol)
            } else {
                scalarAddr.mElement = 1
                if AudioObjectHasProperty(deviceID, &scalarAddr) {
                    AudioObjectSetPropertyData(deviceID, &scalarAddr, 0, nil, size, &vol)
                }
            }
        }
    }

    public func isMuted(for deviceID: AudioDeviceID) -> Bool {
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isMuted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &isMuted)
        return status == noErr && isMuted != 0
    }

    /// Determines if the device is currently processing active audio output from any application
    public func isAudioActivelyPlaying(for deviceID: AudioDeviceID) -> Bool {
        guard deviceID != 0 else { return false }

        var runAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunningSomewhere: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &runAddr, 0, nil, &size, &isRunningSomewhere)
        guard status == noErr else { return false }

        return isRunningSomewhere != 0
    }

    // MARK: - Private Helpers

    private func getStringProperty(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedStr: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanagedStr) { ptr in
            AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let unmanaged = unmanagedStr else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    private func getUInt32Property(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }
}
