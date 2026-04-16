import XCTest

@testable import VoiceFlow

final class PressAndHoldTriggerStateTests: XCTestCase {
    func testKeyDownBeginsAsyncStartWhenIdleAndPermitted() {
        var state = PressAndHoldTriggerState()

        let action = state.handleKeyDown(recorderIsRecording: false)

        XCTAssertEqual(action, .beginAsyncStart)
        XCTAssertTrue(state.isPressed)
        XCTAssertTrue(state.isStartPending)
    }

    func testKeyUpWhileStartPendingWaitsForStartupAndCancelsOnSuccess() {
        var state = PressAndHoldTriggerState()
        _ = state.handleKeyDown(recorderIsRecording: false)

        let keyUpAction = state.handleKeyUp()
        let completionAction = state.handleStartCompletion(success: true)

        XCTAssertEqual(keyUpAction, .awaitPendingStart)
        XCTAssertEqual(completionAction, .cancelStartedRecording)
        XCTAssertFalse(state.isPressed)
        XCTAssertFalse(state.isStartPending)
    }

    func testStartCompletionMarksRecordingStartedWhenKeyStillHeld() {
        var state = PressAndHoldTriggerState()
        _ = state.handleKeyDown(recorderIsRecording: false)

        let completionAction = state.handleStartCompletion(success: true)

        XCTAssertEqual(completionAction, .recordingStarted)
        XCTAssertTrue(state.isPressed)
        XCTAssertFalse(state.isStartPending)
    }

    func testKeyDownKeepsExistingRecordingActive() {
        var state = PressAndHoldTriggerState()

        let action = state.handleKeyDown(recorderIsRecording: true)
        let keyUpAction = state.handleKeyUp()

        XCTAssertEqual(action, .keepExistingRecording)
        XCTAssertEqual(keyUpAction, .stopRecording)
    }

    func testStartFailureResetsState() {
        var state = PressAndHoldTriggerState()
        _ = state.handleKeyDown(recorderIsRecording: false)

        let completionAction = state.handleStartCompletion(success: false)

        XCTAssertEqual(completionAction, .startFailed)
        XCTAssertFalse(state.isPressed)
        XCTAssertFalse(state.isStartPending)
    }

    func testKeyDownBeginsAsyncStartEvenWhenMicrophonePermissionWillBeRequestedLater() {
        var state = PressAndHoldTriggerState()

        let action = state.handleKeyDown(recorderIsRecording: false)

        XCTAssertEqual(action, .beginAsyncStart)
        XCTAssertTrue(state.isPressed)
        XCTAssertTrue(state.isStartPending)
    }
}
