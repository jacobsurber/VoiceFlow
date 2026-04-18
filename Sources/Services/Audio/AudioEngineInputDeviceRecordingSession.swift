import AVFoundation
import AudioToolbox
import Foundation
import os.log

internal protocol InputDeviceRecordingSession: AnyObject {
    var isRecording: Bool { get }
    var averagePower: Float { get }
    var finishHandler: ((Bool) -> Void)? { get set }

    func start() throws
    func stop()
    func cancel()
}

internal final class AudioEngineInputDeviceRecordingSession: InputDeviceRecordingSession {
    private let inputDevice: MicrophoneInputDeviceInfo
    private let outputURL: URL
    private let engine: AVAudioEngine
    private let meterState = MeterState()
    private let stateLock = NSLock()

    private var audioFile: AVAudioFile?
    private var tapInstalled = false
    private var hasFinished = false
    private var stopResult = true

    var finishHandler: ((Bool) -> Void)?
    private(set) var isRecording = false

    var averagePower: Float {
        meterState.averagePower
    }

    init(
        inputDevice: MicrophoneInputDeviceInfo,
        outputURL: URL,
        engine: AVAudioEngine = AVAudioEngine()
    ) {
        self.inputDevice = inputDevice
        self.outputURL = outputURL
        self.engine = engine
    }

    func start() throws {
        let inputNode = engine.inputNode
        let audioUnit = inputNode.auAudioUnit

        guard audioUnit.canPerformInput else {
            throw AudioEngineInputDeviceRecordingError.inputUnavailable(inputDevice.name)
        }

        audioUnit.isInputEnabled = true

        do {
            try audioUnit.setDeviceID(inputDevice.deviceID)
        } catch {
            throw error
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(forWriting: outputURL, settings: recordingFormat.settings)

        inputNode.installTap(onBus: 0, bufferSize: 256, format: recordingFormat) { [weak self] buffer, _ in
            self?.handleIncomingBuffer(buffer)
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() {
        completeRecording(success: stopResult, shouldCleanupFile: false)
    }

    func cancel() {
        completeRecording(success: false, shouldCleanupFile: true)
    }

    private func handleIncomingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let file = currentAudioFile() else { return }

        do {
            try file.write(from: buffer)
            meterState.update(from: buffer)
        } catch {
            Logger.audioRecorder.error(
                "Selected-input recording write failed: \(error.localizedDescription)"
            )
            stateLock.lock()
            stopResult = false
            stateLock.unlock()
            Task { @MainActor [weak self] in
                self?.completeRecording(success: false, shouldCleanupFile: true)
            }
        }
    }

    private func currentAudioFile() -> AVAudioFile? {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !hasFinished else { return nil }
        return audioFile
    }

    private func completeRecording(success: Bool, shouldCleanupFile: Bool) {
        stateLock.lock()
        guard !hasFinished else {
            stateLock.unlock()
            return
        }
        hasFinished = true
        stopResult = success
        let fileURL = outputURL
        audioFile = nil
        stateLock.unlock()

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        isRecording = false

        if shouldCleanupFile {
            try? FileManager.default.removeItem(at: fileURL)
        }

        finishHandler?(success)
    }
}

private final class MeterState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedAveragePower: Float = -160.0

    var averagePower: Float {
        lock.lock()
        defer { lock.unlock() }
        return storedAveragePower
    }

    func update(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let samples = channelData[0]
        var sumSquares: Float = 0
        for index in 0..<frameCount {
            let sample = samples[index]
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Float(frameCount))
        let power = max(-160.0, 20.0 * log10(max(rms, 0.000_000_1)))

        lock.lock()
        storedAveragePower = power
        lock.unlock()
    }
}

internal enum AudioEngineInputDeviceRecordingError: LocalizedError {
    case inputUnavailable(String)
    case deviceSelectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .inputUnavailable(let deviceName):
            return "Input device unavailable for recording: \(deviceName)"
        case .deviceSelectionFailed(let deviceName):
            return "Failed to select recording input device: \(deviceName)"
        }
    }
}
