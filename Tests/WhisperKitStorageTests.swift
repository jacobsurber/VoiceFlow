import XCTest

@testable import VoiceFlow

final class WhisperKitStorageTests: XCTestCase {
    private let requiredCoreMLBundles = [
        "AudioEncoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    override func setUp() {
        super.setUp()
        unsetenv("VOICEFLOW_WHISPERKIT_DOWNLOAD_BASE")
    }

    override func tearDown() {
        unsetenv("VOICEFLOW_WHISPERKIT_DOWNLOAD_BASE")
        super.tearDown()
    }

    func testDownloadBaseDefaultsToDocumentsHuggingFaceBase() {
        let documentsDirectory = URL(fileURLWithPath: "/tmp/voiceflow-documents", isDirectory: true)
        let applicationSupportDirectory = URL(
            fileURLWithPath: "/tmp/voiceflow-app-support", isDirectory: true)

        let downloadBase = WhisperKitStorage.downloadBaseDirectory(
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory
        )
        let storageDirectory = WhisperKitStorage.storageDirectory(
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory
        )

        XCTAssertEqual(downloadBase?.path, "/tmp/voiceflow-documents/huggingface")
        XCTAssertEqual(
            storageDirectory?.path,
            "/tmp/voiceflow-documents/huggingface/models/argmaxinc/whisperkit-coreml"
        )
    }

    func testModelDirectoryFallsBackToLegacyLocationWhenModelExistsThere() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documentsDirectory = root.appendingPathComponent("Documents", isDirectory: true)
        let applicationSupportDirectory = root.appendingPathComponent(
            "Application Support", isDirectory: true)
        let partialDocumentsModelDirectory =
            documentsDirectory
            .appendingPathComponent(
                "huggingface/models/argmaxinc/whisperkit-coreml/\(WhisperModel.base.whisperKitModelName)",
                isDirectory: true
            )
        let legacyModelDirectory =
            applicationSupportDirectory
            .appendingPathComponent(
                "VoiceFlow/huggingface/models/argmaxinc/whisperkit-coreml/\(WhisperModel.base.whisperKitModelName)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: partialDocumentsModelDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacyModelDirectory,
            withIntermediateDirectories: true
        )
        try installCompleteModel(at: legacyModelDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolvedModelDirectory = WhisperKitStorage.modelDirectory(
            for: .base,
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory
        )

        XCTAssertEqual(resolvedModelDirectory?.path, legacyModelDirectory.path)
    }

    func testExistingModelDirectoriesReturnsAllCopiesAcrossSupportedRoots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documentsDirectory = root.appendingPathComponent("Documents", isDirectory: true)
        let applicationSupportDirectory = root.appendingPathComponent(
            "Application Support", isDirectory: true)
        let documentsModelDirectory =
            documentsDirectory
            .appendingPathComponent(
                "huggingface/models/argmaxinc/whisperkit-coreml/\(WhisperModel.small.whisperKitModelName)",
                isDirectory: true
            )
        let legacyModelDirectory =
            applicationSupportDirectory
            .appendingPathComponent(
                "VoiceFlow/huggingface/models/argmaxinc/whisperkit-coreml/\(WhisperModel.small.whisperKitModelName)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: documentsModelDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyModelDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let existingDirectories = WhisperKitStorage.existingModelDirectories(
            for: .small,
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory
        )

        XCTAssertEqual(
            existingDirectories.map(\.path),
            [
                documentsModelDirectory.path,
                legacyModelDirectory.path,
            ])
    }

    func testEnvironmentOverrideResolvesConfiguredDownloadBase() {
        setenv("VOICEFLOW_WHISPERKIT_DOWNLOAD_BASE", "/tmp/custom-whisper-base", 1)

        let downloadBase = WhisperKitStorage.downloadBaseDirectory()
        let storageDirectory = WhisperKitStorage.storageDirectory()

        XCTAssertEqual(downloadBase?.path, "/tmp/custom-whisper-base")
        XCTAssertEqual(
            storageDirectory?.path,
            "/tmp/custom-whisper-base/models/argmaxinc/whisperkit-coreml"
        )
    }

    func testIsModelDownloadedRequiresAllCoreMLBundles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloadBase = root.appendingPathComponent("huggingface", isDirectory: true)
        let modelDirectory =
            downloadBase
            .appendingPathComponent(
                "models/argmaxinc/whisperkit-coreml/\(WhisperModel.base.whisperKitModelName)",
                isDirectory: true
            )

        setenv("VOICEFLOW_WHISPERKIT_DOWNLOAD_BASE", downloadBase.path, 1)
        defer { try? FileManager.default.removeItem(at: root) }

        for bundle in requiredCoreMLBundles {
            let bundleDirectory = modelDirectory.appendingPathComponent(bundle, isDirectory: true)
            try FileManager.default.createDirectory(
                at: bundleDirectory,
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(
                atPath: bundleDirectory.appendingPathComponent("coremldata.bin").path,
                contents: Data([0x1])
            )
        }

        XCTAssertTrue(WhisperKitStorage.isModelDownloaded(.base))
        XCTAssertEqual(WhisperKitStorage.localModelPath(for: .base), modelDirectory.path)
    }

    func testModelDirectoryFindsDownloadsInAccidentalDoubleModelsPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documentsDirectory = root.appendingPathComponent("Documents", isDirectory: true)
        let compatibilityModelDirectory =
            documentsDirectory
            .appendingPathComponent(
                "huggingface/models/models/argmaxinc/whisperkit-coreml/\(WhisperModel.tiny.whisperKitModelName)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: compatibilityModelDirectory,
            withIntermediateDirectories: true
        )
        try installCompleteModel(at: compatibilityModelDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolvedModelDirectory = WhisperKitStorage.modelDirectory(
            for: .tiny,
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: nil
        )

        XCTAssertEqual(resolvedModelDirectory?.path, compatibilityModelDirectory.path)
        XCTAssertTrue(
            WhisperKitStorage.isModelDownloaded(
                .tiny,
                documentsDirectory: documentsDirectory,
                applicationSupportDirectory: nil
            )
        )
    }

    private func installCompleteModel(at modelDirectory: URL) throws {
        for bundle in requiredCoreMLBundles {
            let bundleDirectory = modelDirectory.appendingPathComponent(bundle, isDirectory: true)
            try FileManager.default.createDirectory(
                at: bundleDirectory,
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(
                atPath: bundleDirectory.appendingPathComponent("coremldata.bin").path,
                contents: Data([0x1])
            )
        }
    }
}
