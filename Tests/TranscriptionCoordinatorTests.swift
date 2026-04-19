import XCTest

@testable import Whisp

@MainActor
final class TranscriptionCoordinatorTests: XCTestCase {
    func testShortRecordingFailsBeforeTranscriptionStarts() async {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        do {
            _ = try await TranscriptionCoordinator.shared.processRecording(
                audioURL: audioURL,
                sessionDuration: TranscriptionCoordinator.minimumRecordingDuration - 0.01,
                shouldPaste: false
            )
            XCTFail("Expected short recording error")
        } catch let error as SpeechToTextError {
            XCTAssertEqual(error, .recordingTooShort)
        } catch {
            XCTFail("Expected SpeechToTextError, got \(error)")
        }
    }
}
