import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import os.log

internal struct MicrophoneInputDeviceInfo: Sendable, Equatable {
    let deviceID: AudioDeviceID
    let uid: String
    let name: String
}

internal class MicrophoneVolumeManager {
    static let shared = MicrophoneVolumeManager()

    private var originalVolume: Float32?
    private var audioDeviceID: AudioDeviceID?
    private var isVolumeBoosted = false

    private init() {}

    func boostMicrophoneVolume(deviceUID: String? = nil) async -> Bool {
        guard !isVolumeBoosted else { return true }

        do {
            let deviceID: AudioDeviceID
            if let deviceUID, let selectedDevice = inputDeviceInfo(forSelection: deviceUID) {
                deviceID = selectedDevice.deviceID
            } else {
                deviceID = try await getDefaultInputDevice()
            }

            let currentVolume = try await getInputVolume(deviceID: deviceID)
            originalVolume = currentVolume
            audioDeviceID = deviceID

            let success = try await setInputVolume(deviceID: deviceID, volume: 1.0)
            if success {
                isVolumeBoosted = true
            }

            return success
        } catch {
            Logger.microphoneVolume.error(
                "Failed to boost microphone volume: \(error.localizedDescription)"
            )
            return false
        }
    }

    func restoreMicrophoneVolume() async {
        guard isVolumeBoosted,
            let originalVolume = originalVolume,
            let deviceID = audioDeviceID
        else {
            return
        }

        do {
            _ = try await setInputVolume(deviceID: deviceID, volume: originalVolume)
        } catch {
            Logger.microphoneVolume.error(
                "Failed to restore microphone volume: \(error.localizedDescription)"
            )
        }

        self.originalVolume = nil
        self.audioDeviceID = nil
        isVolumeBoosted = false
    }

    func isVolumeControlAvailable() async -> Bool {
        do {
            let deviceID = try await getDefaultInputDevice()
            return try await hasVolumeControl(deviceID: deviceID)
        } catch {
            return false
        }
    }

    func availableInputDevices() -> [MicrophoneInputDeviceInfo] {
        allAudioDeviceIDs()
            .filter { hasInputChannels(deviceID: $0) }
            .compactMap { deviceInfo(deviceID: $0, allowFallbackValues: false) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func inputDeviceInfo(forSelection selection: String) -> MicrophoneInputDeviceInfo? {
        guard !selection.isEmpty else { return nil }

        let devices = availableInputDevices()
        if let directMatch = devices.first(where: { $0.uid == selection }) {
            return directMatch
        }

        guard let legacyName = legacyAVCaptureDeviceName(for: selection) else {
            return nil
        }

        let matches = devices.filter { $0.name == legacyName }
        return matches.count == 1 ? matches[0] : nil
    }

    func inputDeviceDescription(forSelection selection: String) -> String {
        guard !selection.isEmpty else {
            return "System Default"
        }

        if let resolvedDevice = inputDeviceInfo(forSelection: selection) {
            return "\(resolvedDevice.name) [\(resolvedDevice.uid)]"
        }

        return "Stored selection [\(selection)]"
    }

    func currentDefaultInputDeviceInfoOrNil() async -> MicrophoneInputDeviceInfo? {
        do {
            return try await currentDefaultInputDeviceInfo()
        } catch {
            Logger.microphoneVolume.error(
                "Failed to inspect default input device: \(error.localizedDescription)"
            )
            return nil
        }
    }

    func currentDefaultInputDeviceInfo() async throws -> MicrophoneInputDeviceInfo {
        let deviceID = try await getDefaultInputDevice()
        return deviceInfo(deviceID: deviceID, allowFallbackValues: true)
            ?? MicrophoneInputDeviceInfo(
                deviceID: deviceID,
                uid: "AudioDevice-\(deviceID)",
                name: "Unknown Input Device"
            )
    }

    private func getDefaultInputDevice() async throws -> AudioDeviceID {
        try await withCheckedThrowingContinuation { continuation in
            var deviceID: AudioDeviceID = 0
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                &deviceID
            )

            if status == noErr {
                continuation.resume(returning: deviceID)
            } else {
                continuation.resume(throwing: VolumeError.deviceNotFound)
            }
        }
    }

    private func allAudioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard dataStatus == noErr else { return [] }
        return deviceIDs
    }

    private func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        let bufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList)
        guard status == noErr else { return false }

        let audioBuffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let channelCount = audioBuffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        return channelCount > 0
    }

    private func deviceInfo(
        deviceID: AudioDeviceID,
        allowFallbackValues: Bool
    ) -> MicrophoneInputDeviceInfo? {
        let name = getStringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName)
        let uid = getStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)

        guard allowFallbackValues || (name != nil && uid != nil) else {
            return nil
        }

        return MicrophoneInputDeviceInfo(
            deviceID: deviceID,
            uid: uid ?? "AudioDevice-\(deviceID)",
            name: name ?? "Audio Device \(deviceID)"
        )
    }

    private func legacyAVCaptureDeviceName(for uniqueID: String) -> String? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices.first(where: { $0.uniqueID == uniqueID })?.localizedName
    }

    private func getStringProperty(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { valuePointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                valuePointer
            )
        }

        guard status == noErr, let value else {
            return nil
        }

        return value.takeRetainedValue() as String
    }

    private func hasVolumeControl(deviceID: AudioDeviceID) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            continuation.resume(returning: AudioObjectHasProperty(deviceID, &address))
        }
    }

    private func getInputVolume(deviceID: AudioDeviceID) async throws -> Float32 {
        try await withCheckedThrowingContinuation { continuation in
            var volume: Float32 = 0.0
            var size = UInt32(MemoryLayout<Float32>.size)

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            let status = AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                &volume
            )

            if status == noErr {
                continuation.resume(returning: volume)
            } else {
                continuation.resume(throwing: VolumeError.getVolumeFailed)
            }
        }
    }

    private func setInputVolume(deviceID: AudioDeviceID, volume: Float32) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            var newVolume = volume
            let size = UInt32(MemoryLayout<Float32>.size)

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                size,
                &newVolume
            )

            if status == noErr {
                continuation.resume(returning: true)
            } else if status == kAudioHardwareUnsupportedOperationError {
                continuation.resume(returning: false)
            } else {
                continuation.resume(throwing: VolumeError.setVolumeFailed)
            }
        }
    }
}

internal enum VolumeError: LocalizedError {
    case deviceNotFound
    case getVolumeFailed
    case setVolumeFailed
    case volumeControlNotSupported

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Default input device not found"
        case .getVolumeFailed:
            return "Failed to get current volume"
        case .setVolumeFailed:
            return "Failed to set volume"
        case .volumeControlNotSupported:
            return "Volume control not supported for this device"
        }
    }
}

extension UserDefaults {
    var autoBoostMicrophoneVolume: Bool {
        get { bool(forKey: "autoBoostMicrophoneVolume") }
        set { set(newValue, forKey: "autoBoostMicrophoneVolume") }
    }
}
