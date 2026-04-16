import XCTest

@testable import VoiceFlow

@MainActor
final class MLXModelManagerTests: XCTestCase {
    func testRefreshModelListFindsModelsInsideHubCache() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = "mlx-community/Qwen3-1.7B-4bit"
        let modelDirectory = HuggingFaceCache.modelDirectory(for: repo, rootDirectory: cacheRoot)
        let snapshotDirectory = modelDirectory.appendingPathComponent("snapshots/rev123", isDirectory: true)

        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: snapshotDirectory.appendingPathComponent("model.safetensors").path,
            contents: Data(repeating: 0x1, count: 1024)
        )

        let manager = MLXModelManager(cacheDirectory: cacheRoot, refreshOnInit: false)
        await manager.refreshModelList()

        XCTAssertTrue(manager.downloadedModels.contains(repo))
        XCTAssertNotNil(manager.modelSizes[repo])
        XCTAssertGreaterThan(manager.totalCacheSize, 0)
    }

    func testHuggingFaceCacheUsesHubSubdirectory() {
        let cacheRoot = URL(fileURLWithPath: "/tmp/voiceflow-hf-cache", isDirectory: true)
        let modelDirectory = HuggingFaceCache.modelDirectory(
            for: "mlx-community/parakeet-tdt-0.6b-v3",
            rootDirectory: cacheRoot
        )

        XCTAssertEqual(
            modelDirectory.path,
            "/tmp/voiceflow-hf-cache/hub/models--mlx-community--parakeet-tdt-0.6b-v3"
        )
    }

    func testHuggingFaceCacheRequiresWeightsFile() throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = "mlx-community/parakeet-tdt-0.6b-v3"
        let modelDirectory = HuggingFaceCache.modelDirectory(for: repo, rootDirectory: cacheRoot)
        let refsDirectory = modelDirectory.appendingPathComponent("refs", isDirectory: true)
        let snapshotDirectory = modelDirectory.appendingPathComponent("snapshots/rev123", isDirectory: true)

        try FileManager.default.createDirectory(at: refsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        try "rev123".write(
            to: refsDirectory.appendingPathComponent("main"), atomically: true, encoding: .utf8)

        XCTAssertFalse(HuggingFaceCache.hasUsableModelSnapshot(for: repo, rootDirectory: cacheRoot))
    }

    func testUnusedModelCountExcludesSelectedParakeetRepo() {
        let manager = MLXModelManager(refreshOnInit: false)
        let repo = ParakeetModel.v3Multilingual.rawValue
        let previousRepo = UserDefaults.standard.string(forKey: AppDefaults.Keys.selectedParakeetModel)

        UserDefaults.standard.set(repo, forKey: AppDefaults.Keys.selectedParakeetModel)
        manager.downloadedModels.insert(repo)

        XCTAssertEqual(manager.unusedModelCount, 0)

        if let previousRepo {
            UserDefaults.standard.set(previousRepo, forKey: AppDefaults.Keys.selectedParakeetModel)
        } else {
            UserDefaults.standard.removeObject(forKey: AppDefaults.Keys.selectedParakeetModel)
        }
    }
}
