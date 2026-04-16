import AVFoundation
import XCTest

@testable import Whisp

@MainActor
final class AudioRecorderTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "autoBoostMicrophoneVolume")
        super.tearDown()
    }

    // startRecording() consumes dateProvider() 3 times:
    //   1. debounce check (now)
    //   2. filename timestamp
    //   3. currentSessionStart
    // stopRecording() consumes it 1 time:
    //   4. duration calculation (now)

    func testStartRecordingSetsStateWhenPermissionGranted() async {
        let debounceDate = Date(timeIntervalSince1970: 1_000)
        let timestampDate = Date(timeIntervalSince1970: 1_003)
        let sessionDate = Date(timeIntervalSince1970: 1_005)
        let recorder = makeRecorder(
            dates: [debounceDate, timestampDate, sessionDate],
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )
        recorder.hasPermission = true

        let didStart = await recorder.startRecording()

        XCTAssertTrue(didStart)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.currentSessionStart, sessionDate)
        XCTAssertNil(recorder.lastRecordingDuration)
    }

    func testStartRecordingReturnsFalseWithoutPermission() async {
        var factoryCalled = false
        let recorder = makeRecorder(
            dates: [Date(), Date(), Date()],
            authorizationStatusProvider: { .denied },
            recorderFactory: { _, _ in
                factoryCalled = true
                return MockAVAudioRecorder()
            }
        )
        recorder.hasPermission = false

        let didStart = await recorder.startRecording()

        XCTAssertFalse(didStart)
        XCTAssertFalse(factoryCalled, "Recorder factory should not be used without permission")
        XCTAssertFalse(recorder.isRecording)
    }

    func testInitDoesNotRequestPermissionPromptWhenStatusUndetermined() {
        var requestCount = 0

        let recorder = makeRecorder(
            dates: [],
            authorizationStatusProvider: { .notDetermined },
            permissionRequester: { completion in
                requestCount += 1
                completion(false)
            },
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )

        XCTAssertFalse(recorder.hasPermission)
        XCTAssertEqual(requestCount, 0)
    }

    func testStartRecordingRequestsPermissionOnFirstUseAndStartsWhenGranted() async {
        let debounceDate = Date(timeIntervalSince1970: 5_000)
        let timestampDate = Date(timeIntervalSince1970: 5_003)
        let sessionDate = Date(timeIntervalSince1970: 5_005)
        var requestCount = 0
        var status: AVAuthorizationStatus = .notDetermined

        let recorder = makeRecorder(
            dates: [debounceDate, timestampDate, sessionDate],
            authorizationStatusProvider: { status },
            permissionRequester: { completion in
                requestCount += 1
                status = .authorized
                completion(true)
            },
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )

        let didStart = await recorder.startRecording()

        XCTAssertTrue(didStart)
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(recorder.hasPermission)
        XCTAssertTrue(recorder.isRecording)
    }

    func testStartRecordingReturnsFalseWhenPermissionRequestIsDenied() async {
        var requestCount = 0
        let recorder = makeRecorder(
            dates: [Date()],
            authorizationStatusProvider: { .notDetermined },
            permissionRequester: { completion in
                requestCount += 1
                completion(false)
            },
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )

        let didStart = await recorder.startRecording()

        XCTAssertFalse(didStart)
        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(recorder.hasPermission)
        XCTAssertFalse(recorder.isRecording)
    }

    func testStartRecordingPreventsReentrancy() async {
        let recorder = makeRecorder(
            dates: [
                // First startRecording: debounce, timestamp, sessionStart
                Date(timeIntervalSince1970: 2_000),
                Date(timeIntervalSince1970: 2_001),
                Date(timeIntervalSince1970: 2_002),
                // Second startRecording: debounce (then reentrancy guard fires)
                Date(timeIntervalSince1970: 2_010),
            ],
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )
        recorder.hasPermission = true

        let firstStart = await recorder.startRecording()
        XCTAssertTrue(firstStart, "First start should succeed")
        XCTAssertTrue(recorder.isRecording)

        let secondStart = await recorder.startRecording()

        XCTAssertFalse(secondStart, "Second start should fail due to reentrancy guard")
        XCTAssertTrue(recorder.isRecording, "Should still be recording after failed reentrancy")
    }

    func testStopRecordingSetsDurationAndResetsState() async {
        let sessionStart = Date(timeIntervalSince1970: 3_005)
        let stopDate = Date(timeIntervalSince1970: 3_010)
        let recorder = makeRecorder(
            dates: [
                // startRecording: debounce, timestamp, sessionStart
                Date(timeIntervalSince1970: 3_000),
                Date(timeIntervalSince1970: 3_002),
                sessionStart,
                // stopRecording: now
                stopDate,
            ],
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )
        recorder.hasPermission = true
        let started = await recorder.startRecording()
        XCTAssertTrue(started)

        let url = await recorder.stopRecording()

        XCTAssertNotNil(url)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertEqual(
            recorder.lastRecordingDuration ?? -1,
            stopDate.timeIntervalSince(sessionStart),
            accuracy: 0.001
        )
    }

    func testStopRecordingWhenNotRecordingReturnsNil() async {
        let recorder = makeRecorder(
            dates: [],
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )

        let url = await recorder.stopRecording()

        XCTAssertNil(url)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertNil(recorder.lastRecordingDuration)
    }

    func testCancelRecordingResetsState() async {
        let recorder = makeRecorder(
            dates: [
                // startRecording: debounce, timestamp, sessionStart
                Date(timeIntervalSince1970: 4_000),
                Date(timeIntervalSince1970: 4_001),
                Date(timeIntervalSince1970: 4_002),
            ],
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )
        recorder.hasPermission = true
        let started = await recorder.startRecording()
        XCTAssertTrue(started)

        recorder.cancelRecording()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertNil(recorder.lastRecordingDuration)
    }

    func testStartRecordingReturnsFalseWhenRecorderFactoryThrows() async {
        enum TestError: Error { case failed }

        let recorder = makeRecorder(
            dates: [Date(), Date(), Date()],
            recorderFactory: { _, _ in throw TestError.failed }
        )
        recorder.hasPermission = true

        let didStart = await recorder.startRecording()

        XCTAssertFalse(didStart)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
    }

    // MARK: - Helpers

    private func makeRecorder(
        dates: [Date],
        authorizationStatusProvider: @escaping () -> AVAuthorizationStatus = { .authorized },
        permissionRequester: @escaping (@escaping (Bool) -> Void) -> Void = { completion in
            completion(true)
        },
        recorderFactory: @escaping (URL, [String: Any]) throws -> AVAudioRecorder
    ) -> AudioRecorder {
        let dateProvider = StubDateProvider(dates: dates)
        return AudioRecorder(
            recorderFactory: recorderFactory,
            dateProvider: { dateProvider.nextDate() },
            authorizationStatusProvider: authorizationStatusProvider,
            permissionRequester: permissionRequester
        )
    }
}

private final class StubDateProvider {
    private var dates: [Date]

    init(dates: [Date]) {
        self.dates = dates
    }

    func nextDate() -> Date {
        guard !dates.isEmpty else {
            return Date()
        }
        return dates.removeFirst()
    }
}
