import AVFoundation
import Combine
import Foundation
import os.log

@MainActor
internal class AudioRecorder: NSObject, ObservableObject {
    private enum StopRecordingResult {
        case finishedSuccessfully
        case finishedWithFailure
    }

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var hasPermission = false

    private var audioRecorder: AVAudioRecorder?
    private var inputDeviceRecordingSession: (any InputDeviceRecordingSession)?
    private var recordingURL: URL?
    private var levelUpdateTimer: Timer?
    private let volumeManager: MicrophoneVolumeManager
    private let recorderFactory: (URL, [String: Any]) throws -> AVAudioRecorder
    private let inputDeviceSessionFactory:
        (MicrophoneInputDeviceInfo, URL) throws -> any InputDeviceRecordingSession
    private let dateProvider: () -> Date
    private let authorizationStatusProvider: () -> AVAuthorizationStatus
    private let permissionRequester: (@escaping @Sendable (Bool) -> Void) -> Void
    private let selectedInputDeviceResolver: (String) -> MicrophoneInputDeviceInfo?
    private let defaultInputDeviceProvider: @Sendable () async -> MicrophoneInputDeviceInfo?
    private let diagnosticsLogger: @Sendable (String) -> Void
    private var stopRecordingContinuation: CheckedContinuation<StopRecordingResult, Never>?
    private var stopRecordingTask: Task<URL?, Never>?
    private var stoppingRecorderIdentifier: ObjectIdentifier?
    private var cancelledRecorderIdentifier: ObjectIdentifier?
    private(set) var currentSessionStart: Date?
    private(set) var lastRecordingDuration: TimeInterval?

    private var lastRecordingAttempt: Date?
    private let debounceInterval: TimeInterval = 0.2

    override init() {
        volumeManager = MicrophoneVolumeManager.shared
        recorderFactory = { url, settings in try AVAudioRecorder(url: url, settings: settings) }
        inputDeviceSessionFactory = { device, url in
            AudioEngineInputDeviceRecordingSession(inputDevice: device, outputURL: url)
        }
        dateProvider = { Date() }
        authorizationStatusProvider = { AVCaptureDevice.authorizationStatus(for: .audio) }
        permissionRequester = { completion in
            guard !AppEnvironment.isRunningTests else {
                completion(false)
                return
            }

            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        }
        selectedInputDeviceResolver = { selection in
            MicrophoneVolumeManager.shared.inputDeviceInfo(forSelection: selection)
        }
        defaultInputDeviceProvider = {
            await MicrophoneVolumeManager.shared.currentDefaultInputDeviceInfoOrNil()
        }
        diagnosticsLogger = { message in
            Logger.audioRecorder.info("\(message, privacy: .public)")
        }
        super.init()
        setupRecorder()
        checkMicrophonePermission()
    }

    init(
        volumeManager: MicrophoneVolumeManager = .shared,
        recorderFactory: @escaping (URL, [String: Any]) throws -> AVAudioRecorder,
        inputDeviceSessionFactory:
            @escaping (MicrophoneInputDeviceInfo, URL) throws -> any InputDeviceRecordingSession =
            { device, url in
                AudioEngineInputDeviceRecordingSession(inputDevice: device, outputURL: url)
            },
        dateProvider: @escaping () -> Date = { Date() },
        authorizationStatusProvider: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        permissionRequester: @escaping (@escaping @Sendable (Bool) -> Void) -> Void = { completion in
            guard !AppEnvironment.isRunningTests else {
                completion(false)
                return
            }

            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        },
        selectedInputDeviceResolver: @escaping (String) -> MicrophoneInputDeviceInfo? = { selection in
            MicrophoneVolumeManager.shared.inputDeviceInfo(forSelection: selection)
        },
        defaultInputDeviceProvider: @escaping @Sendable () async -> MicrophoneInputDeviceInfo? =
            {
                await MicrophoneVolumeManager.shared.currentDefaultInputDeviceInfoOrNil()
            },
        diagnosticsLogger: @escaping @Sendable (String) -> Void = { message in
            Logger.audioRecorder.info("\(message, privacy: .public)")
        }
    ) {
        self.volumeManager = volumeManager
        self.recorderFactory = recorderFactory
        self.inputDeviceSessionFactory = inputDeviceSessionFactory
        self.dateProvider = dateProvider
        self.authorizationStatusProvider = authorizationStatusProvider
        self.permissionRequester = permissionRequester
        self.selectedInputDeviceResolver = selectedInputDeviceResolver
        self.defaultInputDeviceProvider = defaultInputDeviceProvider
        self.diagnosticsLogger = diagnosticsLogger
        super.init()
        setupRecorder()
        checkMicrophonePermission()
    }

    private func setupRecorder() {
        // AVAudioSession is not needed on macOS
    }

    func checkMicrophonePermission() {
        let permissionStatus = authorizationStatusProvider()

        switch permissionStatus {
        case .authorized:
            hasPermission = true
        case .denied, .restricted, .notDetermined:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }

    func requestMicrophonePermission() {
        permissionRequester { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.hasPermission = granted
            }
        }
    }

    func startRecording() async -> Bool {
        let now = dateProvider()
        if let last = lastRecordingAttempt, now.timeIntervalSince(last) < debounceInterval {
            Logger.audioRecorder.debug("Recording attempt debounced (too soon after last attempt)")
            return false
        }
        lastRecordingAttempt = now

        guard await ensureMicrophonePermission() else {
            return false
        }

        guard audioRecorder == nil, inputDeviceRecordingSession == nil else {
            return false
        }

        let selectedMicrophoneID =
            UserDefaults.standard.string(forKey: AppDefaults.Keys.selectedMicrophone)
            ?? ""
        let selectedInputDevice = selectedInputDeviceResolver(selectedMicrophoneID)

        await logRecordingInputDiagnostics(
            selectedMicrophoneID: selectedMicrophoneID,
            selectedInputDevice: selectedInputDevice
        )

        if UserDefaults.standard.autoBoostMicrophoneVolume {
            _ = await volumeManager.boostMicrophoneVolume(deviceUID: selectedInputDevice?.uid)
        }

        let tempPath = FileManager.default.temporaryDirectory
        let timestamp = dateProvider().timeIntervalSince1970
        let fileExtension = selectedInputDevice == nil ? "m4a" : "caf"
        let audioFilename = tempPath.appendingPathComponent(
            "recording_\(timestamp).\(fileExtension)"
        )

        recordingURL = audioFilename

        if let selectedInputDevice {
            do {
                let inputSession = try inputDeviceSessionFactory(selectedInputDevice, audioFilename)
                let sessionIdentifier = ObjectIdentifier(inputSession)
                inputSession.finishHandler = { [weak self] success in
                    Task { @MainActor [weak self] in
                        self?.handleInputDeviceSessionFinished(
                            sessionIdentifier: sessionIdentifier,
                            success: success
                        )
                    }
                }
                try inputSession.start()
                inputDeviceRecordingSession = inputSession

                currentSessionStart = dateProvider()
                lastRecordingDuration = nil
                isRecording = true
                startLevelMonitoring()
                return true
            } catch {
                Logger.audioRecorder.error(
                    "Failed to start selected-input recording: \(error.localizedDescription)"
                )
                inputDeviceRecordingSession = nil
                recordingURL = nil
                if UserDefaults.standard.autoBoostMicrophoneVolume {
                    _ = await volumeManager.restoreMicrophoneVolume()
                }
                checkMicrophonePermission()
                return false
            }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            audioRecorder = try recorderFactory(audioFilename, settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            guard audioRecorder?.record() == true else {
                Logger.audioRecorder.error("AVAudioRecorder failed to start recording")
                audioRecorder = nil
                recordingURL = nil

                if UserDefaults.standard.autoBoostMicrophoneVolume {
                    _ = await volumeManager.restoreMicrophoneVolume()
                }

                checkMicrophonePermission()
                return false
            }

            currentSessionStart = dateProvider()
            lastRecordingDuration = nil
            isRecording = true
            startLevelMonitoring()
            return true
        } catch {
            Logger.audioRecorder.error("Failed to start recording: \(error.localizedDescription)")
            audioRecorder = nil
            recordingURL = nil
            if UserDefaults.standard.autoBoostMicrophoneVolume {
                _ = await volumeManager.restoreMicrophoneVolume()
            }
            checkMicrophonePermission()
            return false
        }
    }

    private func logRecordingInputDiagnostics(
        selectedMicrophoneID: String,
        selectedInputDevice: MicrophoneInputDeviceInfo?
    ) async {
        let selectedMicrophoneDescription: String
        if let selectedInputDevice {
            selectedMicrophoneDescription = "\(selectedInputDevice.name) [\(selectedInputDevice.uid)]"
        } else {
            selectedMicrophoneDescription = volumeManager.inputDeviceDescription(
                forSelection: selectedMicrophoneID
            )
        }

        let routeDescription: String
        if let selectedInputDevice {
            routeDescription =
                "Whisp will record from the selected input device name=\(selectedInputDevice.name), uid=\(selectedInputDevice.uid)."
        } else if selectedMicrophoneID.isEmpty {
            routeDescription = "Whisp will record from the system default input."
        } else {
            routeDescription =
                "Selected input unavailable, falling back to the system default input."
        }

        if let defaultInputDevice = await defaultInputDeviceProvider() {
            diagnosticsLogger(
                "Recording start input diagnostics: system default input name=\(defaultInputDevice.name), id=\(defaultInputDevice.deviceID), uid=\(defaultInputDevice.uid), dashboard selection=\(selectedMicrophoneDescription). \(routeDescription)"
            )
            return
        }

        diagnosticsLogger(
            "Recording start input diagnostics: system default input unavailable, dashboard selection=\(selectedMicrophoneDescription). \(routeDescription)"
        )
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch authorizationStatusProvider() {
        case .authorized:
            hasPermission = true
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                permissionRequester { granted in
                    continuation.resume(returning: granted)
                }
            }
            hasPermission = granted
            return granted
        case .denied, .restricted:
            hasPermission = false
            return false
        @unknown default:
            hasPermission = false
            return false
        }
    }

    func stopRecording() async -> URL? {
        if let stopRecordingTask {
            return await stopRecordingTask.value
        }

        if let inputSession = inputDeviceRecordingSession {
            let stopTask = Task { @MainActor [weak self] () -> URL? in
                guard let self else { return nil }

                defer {
                    stopRecordingTask = nil
                }

                let now = dateProvider()
                let sessionDuration = currentSessionStart.map { now.timeIntervalSince($0) }
                lastRecordingDuration = sessionDuration
                currentSessionStart = nil
                let finalRecordingURL = recordingURL

                let stopResult = await waitForInputDeviceSessionToFinish(inputSession)
                if stopResult == .finishedWithFailure {
                    Logger.audioRecorder.error(
                        "Selected-input recording failed during finalization"
                    )
                }

                inputDeviceRecordingSession = nil

                if UserDefaults.standard.autoBoostMicrophoneVolume {
                    _ = await volumeManager.restoreMicrophoneVolume()
                }

                isRecording = false
                stopLevelMonitoring()

                if stopResult == .finishedWithFailure {
                    if let finalRecordingURL {
                        try? FileManager.default.removeItem(at: finalRecordingURL)
                    }
                    recordingURL = nil
                    return nil
                }

                return finalRecordingURL
            }

            stopRecordingTask = stopTask
            return await stopTask.value
        }

        guard let recorder = audioRecorder else {
            return recordingURL
        }

        let stopTask = Task { @MainActor [weak self] () -> URL? in
            guard let self else { return nil }

            defer {
                stopRecordingTask = nil
            }

            let now = dateProvider()
            let sessionDuration = currentSessionStart.map { now.timeIntervalSince($0) }
            lastRecordingDuration = sessionDuration
            currentSessionStart = nil
            let finalRecordingURL = recordingURL

            let stopResult = await waitForRecordingToFinish(recorder)
            if stopResult == .finishedWithFailure {
                Logger.audioRecorder.error("Recording failed during finalization")
            }

            audioRecorder = nil

            if UserDefaults.standard.autoBoostMicrophoneVolume {
                _ = await volumeManager.restoreMicrophoneVolume()
            }

            isRecording = false
            stopLevelMonitoring()

            if stopResult == .finishedWithFailure {
                if let finalRecordingURL {
                    try? FileManager.default.removeItem(at: finalRecordingURL)
                }
                recordingURL = nil
                return nil
            }

            return finalRecordingURL
        }

        stopRecordingTask = stopTask
        return await stopTask.value
    }

    /// Time to wait after the recorder finishes so the AAC encoder can flush
    /// its remaining frames to disk. Without this pause the tail of the
    /// utterance can be truncated when the file is handed to the transcriber.
    static let postStopFlushDelay: UInt64 = 150_000_000  // 150 ms

    private func waitForInputDeviceSessionToFinish(
        _ inputSession: any InputDeviceRecordingSession
    ) async -> StopRecordingResult {
        if !inputSession.isRecording {
            return .finishedSuccessfully
        }

        let sessionIdentifier = ObjectIdentifier(inputSession)

        return await withCheckedContinuation { continuation in
            stoppingRecorderIdentifier = sessionIdentifier
            stopRecordingContinuation = continuation
            inputSession.stop()
        }
    }

    private func waitForRecordingToFinish(_ recorder: AVAudioRecorder) async -> StopRecordingResult {
        if !recorder.isRecording {
            return .finishedSuccessfully
        }

        let recorderIdentifier = ObjectIdentifier(recorder)

        let result = await withCheckedContinuation { continuation in
            stoppingRecorderIdentifier = recorderIdentifier
            stopRecordingContinuation = continuation
            recorder.stop()
        }

        // Give the AAC encoder time to flush buffered frames to the output file.
        try? await Task.sleep(nanoseconds: Self.postStopFlushDelay)

        return result
    }

    private func resolveStopRecordingContinuation(
        result: StopRecordingResult,
        expectedRecorderIdentifier: ObjectIdentifier
    ) {
        guard stoppingRecorderIdentifier == expectedRecorderIdentifier else { return }
        guard let continuation = stopRecordingContinuation else { return }

        stoppingRecorderIdentifier = nil
        stopRecordingContinuation = nil
        continuation.resume(returning: result)
    }

    func cleanupRecording() {
        guard let url = recordingURL else { return }

        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }

        currentSessionStart = nil
        lastRecordingDuration = nil

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.audioRecorder.error("Failed to cleanup recording file: \(error.localizedDescription)")
        }

        recordingURL = nil
    }

    func cancelRecording() {
        let inputSessionToCancel = inputDeviceRecordingSession
        if let inputSessionToCancel {
            cancelledRecorderIdentifier = ObjectIdentifier(inputSessionToCancel)
            inputSessionToCancel.cancel()
        }

        let recorderToCancel = audioRecorder
        if let recorderToCancel {
            cancelledRecorderIdentifier = ObjectIdentifier(recorderToCancel)
            recorderToCancel.stop()
        }

        audioRecorder = nil
        inputDeviceRecordingSession = nil
        currentSessionStart = nil
        lastRecordingDuration = nil

        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }

        isRecording = false
        stopLevelMonitoring()

        if recorderToCancel == nil, inputSessionToCancel == nil {
            cleanupRecording()
        }
    }

    private func startLevelMonitoring() {
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let recorder = self.audioRecorder {
                    recorder.updateMeters()
                    self.audioLevel = self.normalizeLevel(recorder.averagePower(forChannel: 0))
                    return
                }

                if let inputSession = self.inputDeviceRecordingSession {
                    self.audioLevel = self.normalizeLevel(inputSession.averagePower)
                }
            }
        }
    }

    private func stopLevelMonitoring() {
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
        audioLevel = 0.0
    }

    private func normalizeLevel(_ level: Float) -> Float {
        let minDb: Float = -60.0
        let maxDb: Float = 0.0

        let clampedLevel = max(minDb, min(maxDb, level))
        return (clampedLevel - minDb) / (maxDb - minDb)
    }

    private func handleInputDeviceSessionFinished(
        sessionIdentifier: ObjectIdentifier,
        success: Bool
    ) {
        if cancelledRecorderIdentifier == sessionIdentifier {
            cancelledRecorderIdentifier = nil
            cleanupRecording()
            resolveStopRecordingContinuation(
                result: .finishedWithFailure,
                expectedRecorderIdentifier: sessionIdentifier
            )
            return
        }

        if stopRecordingContinuation == nil || stoppingRecorderIdentifier != sessionIdentifier {
            if let activeSession = inputDeviceRecordingSession,
                ObjectIdentifier(activeSession) == sessionIdentifier
            {
                inputDeviceRecordingSession = nil
            }
            isRecording = false
            stopLevelMonitoring()

            if !success {
                cleanupRecording()
            }
            return
        }

        resolveStopRecordingContinuation(
            result: success ? .finishedSuccessfully : .finishedWithFailure,
            expectedRecorderIdentifier: sessionIdentifier
        )
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Logger.audioRecorder.error("Recording finished unsuccessfully")
        }

        Task { @MainActor [weak self] in
            let recorderIdentifier = ObjectIdentifier(recorder)

            if self?.cancelledRecorderIdentifier == recorderIdentifier {
                self?.cancelledRecorderIdentifier = nil
                self?.cleanupRecording()
                self?.resolveStopRecordingContinuation(
                    result: .finishedWithFailure,
                    expectedRecorderIdentifier: recorderIdentifier
                )
                return
            }

            self?.resolveStopRecordingContinuation(
                result: flag ? .finishedSuccessfully : .finishedWithFailure,
                expectedRecorderIdentifier: recorderIdentifier
            )
        }
    }
}
