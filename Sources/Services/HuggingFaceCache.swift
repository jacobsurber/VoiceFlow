import Foundation

internal enum HuggingFaceCache {
    static func homeDirectory(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment["WHISP_HF_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("Whisp/huggingface-cache", isDirectory: true)
        }

        return fileManager.temporaryDirectory.appendingPathComponent("huggingface-cache", isDirectory: true)
    }

    static func hubDirectory(rootDirectory: URL? = nil, fileManager: FileManager = .default) -> URL {
        (rootDirectory ?? homeDirectory(fileManager: fileManager)).appendingPathComponent(
            "hub", isDirectory: true)
    }

    static func modelDirectory(
        for repo: String, rootDirectory: URL? = nil, fileManager: FileManager = .default
    ) -> URL {
        let escaped = repo.replacingOccurrences(of: "/", with: "--")
        return hubDirectory(rootDirectory: rootDirectory, fileManager: fileManager)
            .appendingPathComponent("models--\(escaped)", isDirectory: true)
    }

    static func hasUsableModelSnapshot(
        for repo: String, rootDirectory: URL? = nil, fileManager: FileManager = .default
    ) -> Bool {
        let base = modelDirectory(for: repo, rootDirectory: rootDirectory, fileManager: fileManager)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: base.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            return false
        }

        let refsMain = base.appendingPathComponent("refs/main")
        guard
            let revision = try? String(contentsOf: refsMain, encoding: .utf8).trimmingCharacters(
                in: .whitespacesAndNewlines),
            !revision.isEmpty
        else {
            return false
        }

        let snapshotDirectory = base.appendingPathComponent("snapshots/\(revision)", isDirectory: true)
        guard fileManager.fileExists(atPath: snapshotDirectory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return false
        }

        let snapshotFiles = (try? fileManager.contentsOfDirectory(atPath: snapshotDirectory.path)) ?? []
        let blobFiles =
            (try? fileManager.contentsOfDirectory(
                atPath: base.appendingPathComponent("blobs", isDirectory: true).path)) ?? []
        return snapshotFiles.contains { $0.hasSuffix(".safetensors") }
            || blobFiles.contains { $0.hasSuffix(".safetensors") }
    }
}
