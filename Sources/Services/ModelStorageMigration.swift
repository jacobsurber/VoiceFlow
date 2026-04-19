import Foundation
import os.log

/// One-shot migration that moves model assets from legacy locations into the unified
/// `~/Documents/Models/` tree.
///
/// Call `ModelStorageMigration.migrateIfNeeded()` early in the app lifecycle (e.g. AppDelegate).
/// The migration is idempotent: a sentinel file records completion so subsequent launches skip work.
internal enum ModelStorageMigration {
    private static let logger = Logger(subsystem: "com.whisp.app", category: "ModelStorageMigration")
    private static let sentinelFileName = ".migration-v1-complete"

    /// Run migration exactly once. Safe to call on every launch.
    static func migrateIfNeeded(fileManager: FileManager = .default) {
        let sentinel = ModelStoragePaths.modelsRoot(fileManager: fileManager)
            .appendingPathComponent(sentinelFileName)

        guard !fileManager.fileExists(atPath: sentinel.path) else {
            return
        }

        logger.info("Starting model storage migration")
        ModelStoragePaths.ensureDirectoriesExist(fileManager: fileManager)

        migrateWhisperKitModels(fileManager: fileManager)
        migrateHuggingFaceCache(fileManager: fileManager)

        // Write sentinel
        fileManager.createFile(atPath: sentinel.path, contents: Data(), attributes: nil)
        logger.info("Model storage migration complete")
    }

    // MARK: - WhisperKit migration

    /// Move WhisperKit models from legacy bases into the unified WhisperKit base.
    /// Legacy bases:
    ///   - `~/Documents/huggingface`                             (default HubApi path)
    ///   - `~/Library/Application Support/Whisp/huggingface`     (old app-managed path)
    ///   - `~/Library/Application Support/Whisp/Models/WhisperKit` (previous unified path)
    ///   - `~/Library/Application Support/CuePrompt/huggingface` (CuePrompt's current path)
    ///
    /// Both may have models at `<base>/models/argmaxinc/whisperkit-coreml/<variant>/`
    /// or at the accidental double-models path `<base>/models/models/argmaxinc/whisperkit-coreml/<variant>/`.
    private static func migrateWhisperKitModels(fileManager: FileManager) {
        let unifiedBase = ModelStoragePaths.whisperKitBase(fileManager: fileManager)
        let repositoryPath = "models/argmaxinc/whisperkit-coreml"
        let doubleModelsRepositoryPath = "models/models/argmaxinc/whisperkit-coreml"

        for legacyBase in ModelStoragePaths.legacyWhisperKitBases(fileManager: fileManager) {
            for subpath in [repositoryPath, doubleModelsRepositoryPath] {
                let legacyRepoRoot = legacyBase.appendingPathComponent(subpath, isDirectory: true)
                moveContents(from: legacyRepoRoot,
                             to: unifiedBase.appendingPathComponent(repositoryPath, isDirectory: true),
                             fileManager: fileManager)
            }
        }
    }

    // MARK: - HuggingFace cache migration

    /// Move the legacy `~/Library/Application Support/Whisp/huggingface-cache/hub/` contents
    /// into the unified `HuggingFace/hub/` directory.
    private static func migrateHuggingFaceCache(fileManager: FileManager) {
        guard let legacyHome = ModelStoragePaths.legacyHuggingFaceHome(fileManager: fileManager) else {
            return
        }

        let legacyHub = legacyHome.appendingPathComponent("hub", isDirectory: true)
        let unifiedHub = ModelStoragePaths.huggingFaceHome(fileManager: fileManager)
            .appendingPathComponent("hub", isDirectory: true)

        moveContents(from: legacyHub, to: unifiedHub, fileManager: fileManager)
    }

    // MARK: - Helpers

    /// Move each child item from `source` into `destination`, skipping items that already exist
    /// at the destination. Creates `destination` if needed.
    private static func moveContents(from source: URL, to destination: URL, fileManager: FileManager) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), !children.isEmpty else {
            return
        }

        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        for child in children {
            let targetURL = destination.appendingPathComponent(child.lastPathComponent)
            guard !fileManager.fileExists(atPath: targetURL.path) else {
                logger.info("Skipping existing item at \(targetURL.path)")
                continue
            }

            do {
                try fileManager.moveItem(at: child, to: targetURL)
                logger.info("Migrated \(child.lastPathComponent) to \(destination.path)")
            } catch {
                logger.error("Failed to migrate \(child.path): \(error.localizedDescription)")
            }
        }
    }
}
