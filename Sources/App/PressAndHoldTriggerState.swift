import Foundation

internal struct PressAndHoldTriggerState {
    enum KeyDownAction: Equatable {
        case ignore
        case beginAsyncStart
        case keepExistingRecording
    }

    enum StartCompletionAction: Equatable {
        case noOp
        case recordingStarted
        case cancelStartedRecording
        case startFailed
    }

    enum KeyUpAction: Equatable {
        case ignore
        case awaitPendingStart
        case stopRecording
    }

    private(set) var isPressed = false
    private(set) var isStartPending = false

    mutating func handleKeyDown(recorderIsRecording: Bool) -> KeyDownAction {
        if recorderIsRecording {
            isPressed = true
            isStartPending = false
            return .keepExistingRecording
        }

        guard !isPressed, !isStartPending else {
            return .ignore
        }

        isPressed = true
        isStartPending = true
        return .beginAsyncStart
    }

    mutating func handleStartCompletion(success: Bool) -> StartCompletionAction {
        guard isStartPending else {
            return .noOp
        }

        isStartPending = false

        guard success else {
            isPressed = false
            return .startFailed
        }

        return isPressed ? .recordingStarted : .cancelStartedRecording
    }

    mutating func handleKeyUp() -> KeyUpAction {
        guard isPressed || isStartPending else {
            return .ignore
        }

        isPressed = false

        return isStartPending ? .awaitPendingStart : .stopRecording
    }

    mutating func reset() {
        isPressed = false
        isStartPending = false
    }
}
