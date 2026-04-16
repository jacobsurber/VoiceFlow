import XCTest
@testable import Whisp

@MainActor
final class ErrorPresenterTests: XCTestCase {
    @MainActor override func setUp() {
        super.setUp()
        ErrorPresenter.shared.isTestEnvironment = true
    }

    // MARK: - Error Presentation

    @MainActor func testShowErrorDoesNotCrashInTestEnvironment() {
        // ErrorPresenter skips UI in test mode; just verify no crash
        XCTAssertNoThrow(ErrorPresenter.shared.showError("Something went wrong"))
    }

    @MainActor func testShowErrorWithAPIKeyMessage() {
        XCTAssertNoThrow(ErrorPresenter.shared.showError("Invalid API key provided"))
    }

    @MainActor func testShowErrorWithMicrophoneMessage() {
        XCTAssertNoThrow(ErrorPresenter.shared.showError("Microphone permission denied"))
    }

    @MainActor func testShowErrorWithConnectionMessage() {
        XCTAssertNoThrow(ErrorPresenter.shared.showError("Internet connection dropped"))
    }

    @MainActor func testShowErrorWithTranscriptionMessage() {
        XCTAssertNoThrow(ErrorPresenter.shared.showError("Transcription failed for the audio file"))
    }
}
