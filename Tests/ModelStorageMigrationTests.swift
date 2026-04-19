import XCTest

@testable import Whisp

final class ModelStorageMigrationTests: XCTestCase {
    private var tempRoot: URL!
    private var fakeAppSupport: URL!
    private var fakeDocuments: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("whisp-migration-\(UUID().uuidString)", isDirectory: true)
        fakeAppSupport = tempRoot.appendingPathComponent("Library/Application Support", isDirectory: true)
        fakeDocuments = tempRoot.appendingPathComponent("Documents", isDirectory: true)
        try? fileManager.createDirectory(at: fakeAppSupport, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: fakeDocuments, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: tempRoot)
        super.tearDown()
    }

    // MARK: - ModelStoragePaths

    func testModelsRootIsUnderDocuments() {
        let root = ModelStoragePaths.modelsRoot()
        XCTAssertTrue(root.path.contains("Documents/Models"))
    }

    func testWhisperKitBaseIsUnderModelsRoot() {
        let base = ModelStoragePaths.whisperKitBase()
        XCTAssertTrue(base.path.hasSuffix("Models/WhisperKit"))
    }

    func testHuggingFaceHomeIsUnderModelsRoot() {
        let home = ModelStoragePaths.huggingFaceHome()
        XCTAssertTrue(home.path.hasSuffix("Models/HuggingFace"))
    }

    func testLegacyWhisperKitBasesContainsAllLegacyLocations() {
        let bases = ModelStoragePaths.legacyWhisperKitBases()
        XCTAssertEqual(bases.count, 4)
        XCTAssertTrue(bases[0].path.contains("Documents/huggingface"))
        XCTAssertTrue(bases[1].path.contains("Whisp/huggingface"))
        XCTAssertTrue(bases[2].path.contains("Whisp/Models/WhisperKit"))
        XCTAssertTrue(bases[3].path.contains("CuePrompt/huggingface"))
    }

    func testLegacyHuggingFaceHomePointsToOldCache() {
        let legacy = ModelStoragePaths.legacyHuggingFaceHome()
        XCTAssertNotNil(legacy)
        XCTAssertTrue(legacy!.path.contains("Whisp/huggingface-cache"))
    }

    func testEnsureDirectoriesExistCreatesExpectedPaths() {
        let root = tempRoot.appendingPathComponent("AppSupport/Whisp/Models", isDirectory: true)
        // Use a custom path to avoid modifying real Application Support
        let whisperKitDir = root.appendingPathComponent("WhisperKit", isDirectory: true)
        let hfDir = root.appendingPathComponent("HuggingFace", isDirectory: true)

        try? fileManager.createDirectory(at: whisperKitDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: hfDir, withIntermediateDirectories: true)

        var isDir: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: whisperKitDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertTrue(fileManager.fileExists(atPath: hfDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - HuggingFaceCache unified path

    func testHuggingFaceCacheHomeDirectoryUsesUnifiedPath() {
        let home = HuggingFaceCache.homeDirectory()
        XCTAssertTrue(home.path.contains("Documents/Models/HuggingFace"),
                       "Expected unified path but got: \(home.path)")
    }

    func testHuggingFaceCacheHomeDirectoryRespectsEnvironmentOverride() {
        let original = ProcessInfo.processInfo.environment["WHISP_HF_HOME"]
        setenv("WHISP_HF_HOME", "/tmp/custom-hf-override", 1)
        defer {
            if let original {
                setenv("WHISP_HF_HOME", original, 1)
            } else {
                unsetenv("WHISP_HF_HOME")
            }
        }

        let home = HuggingFaceCache.homeDirectory()
        XCTAssertEqual(home.path, "/tmp/custom-hf-override")
    }

    // MARK: - WhisperKitStorage unified primary path

    func testWhisperKitStorageDownloadBaseUsesUnifiedPath() {
        unsetenv("WHISP_WHISPERKIT_DOWNLOAD_BASE")

        let base = WhisperKitStorage.downloadBaseDirectory()
        XCTAssertNotNil(base)
        XCTAssertTrue(base!.path.contains("Documents/Models/WhisperKit"),
                       "Expected unified WhisperKit base but got: \(base!.path)")
    }

    func testWhisperKitStorageStillFindsModelsAtLegacyLocations() throws {
        unsetenv("WHISP_WHISPERKIT_DOWNLOAD_BASE")

        let documentsBase = fakeDocuments.appendingPathComponent("huggingface", isDirectory: true)
        let legacyModelDir = documentsBase
            .appendingPathComponent(
                "models/argmaxinc/whisperkit-coreml/\(WhisperModel.base.whisperKitModelName)",
                isDirectory: true
            )

        try fileManager.createDirectory(at: legacyModelDir, withIntermediateDirectories: true)
        try installCompleteWhisperKitModel(at: legacyModelDir)

        let isDownloaded = WhisperKitStorage.isModelDownloaded(
            .base,
            documentsDirectory: fakeDocuments,
            applicationSupportDirectory: fakeAppSupport
        )
        XCTAssertTrue(isDownloaded, "Should still find models at legacy ~/Documents/huggingface location")
    }

    // MARK: - Helpers

    private let requiredCoreMLBundles = [
        "AudioEncoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    private func installCompleteWhisperKitModel(at directory: URL) throws {
        for bundle in requiredCoreMLBundles {
            let bundleDir = directory.appendingPathComponent(bundle, isDirectory: true)
            try fileManager.createDirectory(at: bundleDir, withIntermediateDirectories: true)
            fileManager.createFile(
                atPath: bundleDir.appendingPathComponent("coremldata.bin").path,
                contents: Data([0x1])
            )
        }
    }
}
