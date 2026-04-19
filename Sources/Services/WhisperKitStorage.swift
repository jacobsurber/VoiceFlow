import Foundation

internal enum WhisperKitStorage {
    // HubApi expects a Hugging Face base like ~/Documents/huggingface and stores model repos under
    // <base>/models/<owner>/<repo>. Keep probing the accidental older base that already includes
    // /models so downloads created by the earlier regression still resolve and delete correctly.
    private static let downloadBaseOverrideKey = "WHISP_WHISPERKIT_DOWNLOAD_BASE"
    private static let documentsHubBaseRelativePath = "huggingface"
    private static let legacyHubBaseRelativePath = "Whisp/huggingface"
    private static let modelsPathComponent = "models"
    private static let repositoryPath = "argmaxinc/whisperkit-coreml"

    // Unified primary download base under app-managed storage.
    // Legacy ~/Documents/huggingface and ~/Library/Application Support/Whisp/huggingface
    // are still probed as read-only fallbacks for models that have not been migrated.

    // During download, the folder may exist with partial contents, so "is downloaded" checks for the
    // three required CoreML bundles with sentinel files. WhisperKit automatically downloads tokenizers
    // from HuggingFace Hub if not present locally.
    private static let requiredCoreMLBundles = [
        "AudioEncoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    static func downloadBaseDirectory(
        documentsDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = downloadBaseOverride(), !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return preferredDownloadBases(
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager
        ).first
    }

    static func storageDirectory(
        documentsDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        let repoRoots = candidateRepositoryRoots(
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager
        )

        return repoRoots.first { repositoryRootContainsInstalledModels($0, fileManager: fileManager) }
            ?? repoRoots.first { directoryExists($0, fileManager: fileManager) }
            ?? repoRoots.first
    }

    static func modelDirectory(
        for model: WhisperModel,
        documentsDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidates = candidateRepositoryRoots(
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager
        ).map { $0.appendingPathComponent(model.whisperKitModelName, isDirectory: true) }

        if let completeDirectory = candidates.first(where: {
            isCompleteModelDirectory($0, fileManager: fileManager)
        }) {
            return completeDirectory
        }

        return candidates.first { directoryExists($0, fileManager: fileManager) } ?? candidates.first
    }

    static func existingModelDirectories(
        for model: WhisperModel,
        documentsDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [URL] {
        candidateRepositoryRoots(
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager
        ).map { $0.appendingPathComponent(model.whisperKitModelName, isDirectory: true) }
            .filter { directoryExists($0, fileManager: fileManager) }
    }

    static func isModelDownloaded(
        _ model: WhisperModel,
        documentsDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        let existingDirectories = existingModelDirectories(
            for: model,
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager
        )

        return existingDirectories.contains { isCompleteModelDirectory($0, fileManager: fileManager) }
    }

    static func localModelPath(
        for model: WhisperModel,
        documentsDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        guard
            isModelDownloaded(
                model,
                documentsDirectory: documentsDirectory,
                applicationSupportDirectory: applicationSupportDirectory,
                fileManager: fileManager
            ),
            let url = modelDirectory(
                for: model,
                documentsDirectory: documentsDirectory,
                applicationSupportDirectory: applicationSupportDirectory,
                fileManager: fileManager
            )
        else {
            return nil
        }
        return url.path
    }

    static func ensureBaseDirectoryExists(fileManager: FileManager = .default) {
        guard let baseDirectory = downloadBaseDirectory(fileManager: fileManager) else { return }
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    private static func preferredDownloadBases(
        documentsDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [URL] {
        if let override = downloadBaseOverride(), !override.isEmpty {
            return [URL(fileURLWithPath: override, isDirectory: true)]
        }

        // Primary: unified app-managed location
        let unifiedBase = ModelStoragePaths.whisperKitBase(fileManager: fileManager)

        // Legacy fallbacks (read-only, for models that haven't been migrated yet)
        let documentsBase =
            (documentsDirectory
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first)?
            .appendingPathComponent(documentsHubBaseRelativePath, isDirectory: true)
        let legacyBase =
            (applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)?
            .appendingPathComponent(legacyHubBaseRelativePath, isDirectory: true)

        return [unifiedBase, documentsBase, legacyBase].compactMap { $0 }
    }

    private static func candidateDownloadBases(
        documentsDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [URL] {
        let preferredBases = preferredDownloadBases(
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager
        )

        var candidates: [URL] = []
        for base in preferredBases {
            candidates.append(base)
            candidates.append(base.appendingPathComponent(modelsPathComponent, isDirectory: true))
        }

        return uniqueURLs(candidates)
    }

    private static func candidateRepositoryRoots(
        documentsDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [URL] {
        candidateDownloadBases(
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager
        ).map { repositoryRoot(forDownloadBase: $0) }
    }

    private static func repositoryRoot(forDownloadBase baseDirectory: URL) -> URL {
        baseDirectory
            .appendingPathComponent(modelsPathComponent, isDirectory: true)
            .appendingPathComponent(repositoryPath, isDirectory: true)
    }

    private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func repositoryRootContainsInstalledModels(_ url: URL, fileManager: FileManager) -> Bool {
        guard directoryExists(url, fileManager: fileManager) else { return false }

        guard
            let children = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return false
        }

        return children.contains { child in
            guard let isDirectory = try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
                return false
            }
            return isDirectory == true
        }
    }

    private static func isCompleteModelDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard directoryExists(url, fileManager: fileManager) else { return false }

        for bundle in requiredCoreMLBundles {
            let bundleURL = url.appendingPathComponent(bundle, isDirectory: true)
            var isBundleDir: ObjCBool = false
            guard fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isBundleDir),
                isBundleDir.boolValue
            else {
                return false
            }

            let sentinel = bundleURL.appendingPathComponent("coremldata.bin")
            if !fileManager.fileExists(atPath: sentinel.path) {
                return false
            }
        }

        return true
    }

    private static func downloadBaseOverride() -> String? {
        downloadBaseOverrideKey.withCString { keyPointer in
            guard let valuePointer = getenv(keyPointer), valuePointer.pointee != 0 else {
                return nil
            }
            return String(cString: valuePointer)
        }
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }
}
