import AVFoundation
import XCTest

@testable import Whisp

final class AudioValidatorTests: XCTestCase {

    func testValidateAudioFileReturnsFileNotFound() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).wav")

        let result = await AudioValidator.validateAudioFile(at: missingURL)

        guard case .invalid(.fileNotFound) = result else {
            return XCTFail("Expected fileNotFound, got \(result)")
        }
    }

    func testValidateAudioFileRejectsEmptyFile() async throws {
        let url = try temporaryFile(extension: "wav", contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await AudioValidator.validateAudioFile(at: url)

        guard case .invalid(.emptyFile) = result else {
            return XCTFail("Expected emptyFile, got \(result)")
        }
    }

    func testValidateAudioFileRejectsUnsupportedFormat() async throws {
        let url = try temporaryFile(extension: "txt", contents: Data([0x00, 0x01]))
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await AudioValidator.validateAudioFile(at: url)

        guard case .invalid(.unsupportedFormat("txt")) = result else {
            return XCTFail("Expected unsupportedFormat(txt), got \(result)")
        }
    }

    func testValidateAudioFileReturnsValidForWellFormedAudio() async throws {
        let url = try makeValidAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await AudioValidator.validateAudioFile(at: url)

        guard case .valid(let info) = result else {
            return XCTFail("Expected valid result, got \(result)")
        }

        XCTAssertTrue(result.isValid)
        XCTAssertGreaterThan(info.sampleRate, 0)
        XCTAssertGreaterThan(info.channelCount, 0)
        XCTAssertGreaterThan(info.duration, 0)
        XCTAssertGreaterThan(info.fileSize, 0)
    }

    func testValidateAudioFileRejectsSilentAudio() async throws {
        let url = try makeSilentAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await AudioValidator.validateAudioFile(at: url)

        guard case .invalid(.silentAudio) = result else {
            return XCTFail("Expected silentAudio, got \(result)")
        }
    }

    func testValidateAudioFileAcceptsAudioWithLeadingSilence() async throws {
        let url = try makeLeadingSilenceAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await AudioValidator.validateAudioFile(at: url)

        guard case .valid = result else {
            return XCTFail("Expected valid audio with leading silence, got \(result)")
        }
    }

    func testValidateAudioFileAcceptsAudioWithMidFileSpeech() async throws {
        let url = try makeMidFileSpeechAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await AudioValidator.validateAudioFile(at: url)

        guard case .valid = result else {
            return XCTFail("Expected valid audio with mid-file speech, got \(result)")
        }
    }

    func testValidateAudioFileDetectsCorruptedAudio() async throws {
        let url = try makeCorruptedAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await AudioValidator.validateAudioFile(at: url)

        guard case .invalid(.corruptedFile) = result else {
            return XCTFail("Expected corruptedFile, got \(result)")
        }
    }

    func testIsFormatSupportedMatchesKnownExtensions() {
        let supported = URL(fileURLWithPath: "/tmp/audio.mp3")
        let unsupported = URL(fileURLWithPath: "/tmp/audio.doc")

        XCTAssertTrue(AudioValidator.isFormatSupported(url: supported))
        XCTAssertFalse(AudioValidator.isFormatSupported(url: unsupported))
    }

    func testIsFileSizeValidEnforcesLimit() throws {
        let smallFile = try temporaryFile(extension: "wav", contents: Data(repeating: 0xAA, count: 1_024))
        let largeFile = try temporaryFile(extension: "wav", contents: Data(repeating: 0xBB, count: 2_000_000))
        defer {
            try? FileManager.default.removeItem(at: smallFile)
            try? FileManager.default.removeItem(at: largeFile)
        }

        XCTAssertTrue(AudioValidator.isFileSizeValid(url: smallFile, maxSizeInMB: 1))
        XCTAssertFalse(AudioValidator.isFileSizeValid(url: largeFile, maxSizeInMB: 1))
    }

    // MARK: - Helpers

    private func temporaryFile(extension fileExtension: String, contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioValidatorTests-\(UUID().uuidString).\(fileExtension)")
        FileManager.default.createFile(atPath: url.path, contents: contents, attributes: nil)
        return url
    }

    private func makeValidAudioFile() throws -> URL {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            throw NSError(
                domain: "AudioValidatorTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create audio format"])
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioValidatorTests-valid-\(UUID().uuidString).wav")

        let frameCount: AVAudioFrameCount = 1_024
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(
                domain: "AudioValidatorTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create buffer"])
        }
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            let samples = channelData[0]
            for index in 0..<Int(frameCount) {
                samples[index] = sin(Float(index) * 0.1) * 0.25
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func makeSilentAudioFile() throws -> URL {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            throw NSError(
                domain: "AudioValidatorTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create audio format"])
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioValidatorTests-silent-\(UUID().uuidString).wav")

        let frameCount: AVAudioFrameCount = 1_024
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(
                domain: "AudioValidatorTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create buffer"])
        }
        buffer.frameLength = frameCount

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func makeLeadingSilenceAudioFile() throws -> URL {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            throw NSError(
                domain: "AudioValidatorTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create audio format"])
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioValidatorTests-leading-silence-\(UUID().uuidString).wav")

        let silentFrames: AVAudioFrameCount = 44_100
        let toneFrames: AVAudioFrameCount = 8_192
        let totalFrames = silentFrames + toneFrames

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw NSError(
                domain: "AudioValidatorTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create buffer"])
        }
        buffer.frameLength = totalFrames

        if let channelData = buffer.floatChannelData {
            let samples = channelData[0]
            for index in Int(silentFrames)..<Int(totalFrames) {
                let toneIndex = index - Int(silentFrames)
                samples[index] = sin(Float(toneIndex) * 0.1) * 0.25
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func makeMidFileSpeechAudioFile() throws -> URL {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            throw NSError(
                domain: "AudioValidatorTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create audio format"])
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioValidatorTests-mid-speech-\(UUID().uuidString).wav")

        let leadingSilentFrames: AVAudioFrameCount = 70_000
        let toneFrames: AVAudioFrameCount = 4_096
        let trailingSilentFrames: AVAudioFrameCount = 120_000
        let totalFrames = leadingSilentFrames + toneFrames + trailingSilentFrames

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw NSError(
                domain: "AudioValidatorTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create buffer"])
        }
        buffer.frameLength = totalFrames

        if let channelData = buffer.floatChannelData {
            let samples = channelData[0]
            let toneStartIndex = Int(leadingSilentFrames)
            let toneEndIndex = Int(leadingSilentFrames + toneFrames)
            for index in toneStartIndex..<toneEndIndex {
                let toneIndex = index - toneStartIndex
                samples[index] = sin(Float(toneIndex) * 0.1) * 0.25
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func makeCorruptedAudioFile() throws -> URL {
        let payload = Data("not a real wav file".utf8)
        return try temporaryFile(extension: "wav", contents: payload)
    }
}
