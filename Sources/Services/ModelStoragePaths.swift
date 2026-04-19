import Foundation
import os.log

/// Single source of truth for all model storage locations.
///
/// Everything lives under `~/Documents/Models/`:
///   - `WhisperKit/`     — HubApi base for WhisperKit CoreML models (shared with CuePrompt)
///   - `HuggingFace/`    — HF_HOME for MLX, Parakeet, Gemma, and semantic-correction models
///
/// Legacy locations (probed during migration, never written to by new code):
///   - `~/Documents/huggingface`
///   - `~/Library/Application Support/Whisp/huggingface`
///   - `~/Library/Application Support/Whisp/Models/WhisperKit`
///   - `~/Library/Application Support/Whisp/huggingface-cache`
///   - `~/Library/Application Support/CuePrompt/huggingface`
internal enum ModelStoragePaths {
    private static let logger = Logger(subsystem: "com.whisp.app", category: "ModelStoragePaths")

    // MARK: - Unified root

    static func modelsRoot(fileManager: FileManager = .default) -> URL {
        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documents.appendingPathComponent("Models", isDirectory: true)
        }
        return fileManager.temporaryDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    // MARK: - WhisperKit

    /// The HubApi download base for WhisperKit CoreML models.
    /// Models end up at `<base>/models/argmaxinc/whisperkit-coreml/<variant>/`.
    static func whisperKitBase(fileManager: FileManager = .default) -> URL {
        modelsRoot(fileManager: fileManager).appendingPathComponent("WhisperKit", isDirectory: true)
    }

    // MARK: - HuggingFace (MLX, Parakeet, Gemma, semantic correction)

    /// HF_HOME root for all HuggingFace-Hub-based downloads.
    /// The hub cache lives at `<root>/hub/models--<owner>--<repo>/`.
    static func huggingFaceHome(fileManager: FileManager = .default) -> URL {
        modelsRoot(fileManager: fileManager).appendingPathComponent("HuggingFace", isDirectory: true)
    }

    // MARK: - Legacy locations (read-only, for migration)

    /// All legacy WhisperKit base directories that may contain downloaded models.
    static func legacyWhisperKitBases(fileManager: FileManager = .default) -> [URL] {
        var bases: [URL] = []

        // ~/Documents/huggingface (the accidental default WhisperKit used)
        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            bases.append(documents.appendingPathComponent("huggingface", isDirectory: true))
        }

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            // ~/Library/Application Support/Whisp/huggingface (legacy app-managed location)
            bases.append(
                appSupport.appendingPathComponent("Whisp/huggingface", isDirectory: true))

            // ~/Library/Application Support/Whisp/Models/WhisperKit (previous unified location)
            bases.append(
                appSupport.appendingPathComponent("Whisp/Models/WhisperKit", isDirectory: true))

            // ~/Library/Application Support/CuePrompt/huggingface (CuePrompt's current location)
            bases.append(
                appSupport.appendingPathComponent("CuePrompt/huggingface", isDirectory: true))
        }

        return bases
    }

    /// The legacy HuggingFace cache directory (`~/Library/Application Support/Whisp/huggingface-cache`).
    static func legacyHuggingFaceHome(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Whisp/huggingface-cache", isDirectory: true)
    }

    // MARK: - Directory creation

    static func ensureDirectoriesExist(fileManager: FileManager = .default) {
        let directories = [
            whisperKitBase(fileManager: fileManager),
            huggingFaceHome(fileManager: fileManager),
        ]

        for directory in directories {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
