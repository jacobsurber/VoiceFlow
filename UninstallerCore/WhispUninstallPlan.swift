import Foundation
import Security

public typealias WhispProcessRunner = (_ executablePath: String, _ arguments: [String]) -> (
    String, String, Int32
)

public struct WhispUninstallItem: Identifiable, Hashable, Sendable {
    public enum Action: Hashable, Sendable {
        case removePaths([URL])
        case clearPreferenceDomain(domain: String, paths: [URL])
        case removeKeychainItems(service: String, accounts: [String])
        case resetPrivacyPermissions(bundleIdentifier: String, services: [String])
    }

    public let id: String
    public let title: String
    public let detail: String
    public let action: Action
    public let isSelectedByDefault: Bool
    public let requiresExplicitSelection: Bool

    public init(
        id: String,
        title: String,
        detail: String,
        action: Action,
        isSelectedByDefault: Bool,
        requiresExplicitSelection: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.action = action
        self.isSelectedByDefault = isSelectedByDefault
        self.requiresExplicitSelection = requiresExplicitSelection
    }

    public var paths: [URL] {
        switch action {
        case .removePaths(let paths):
            return paths
        case .clearPreferenceDomain(_, let paths):
            return paths
        case .removeKeychainItems, .resetPrivacyPermissions:
            return []
        }
    }
}

public struct WhispUninstallRunResult: Sendable {
    public let removedPaths: [URL]
    public let skippedPaths: [URL]
    public let warnings: [String]

    public init(removedPaths: [URL], skippedPaths: [URL], warnings: [String]) {
        self.removedPaths = removedPaths
        self.skippedPaths = skippedPaths
        self.warnings = warnings
    }
}

public enum WhispUninstallError: Error, LocalizedError {
    case failedToRemove(URL, underlying: String)
    case failedToDeleteKeychainItem(service: String, account: String, status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .failedToRemove(let url, let underlying):
            return "Failed to remove \(url.path): \(underlying)"
        case .failedToDeleteKeychainItem(let service, let account, let status):
            return "Failed to delete keychain item \(service)/\(account): \(status)"
        }
    }
}

public enum WhispInstallLayout {
    public static let appBundleIdentifier = "com.whisp.app"
    public static let uninstallerBundleIdentifier = "com.whisp.app.uninstaller"
    public static let keychainService = "Whisp"
    public static let keychainAccounts = ["OpenAI", "Gemini"]
    public static let privacyServices = ["Microphone", "Accessibility", "ListenEvent"]

    public static func defaultItems(fileManager: FileManager = .default) -> [WhispUninstallItem] {
        let home = fileManager.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let applicationSupport = library.appendingPathComponent("Application Support", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)

        let applicationsPaths = [
            URL(fileURLWithPath: "/Applications/Whisp.app", isDirectory: true),
            home.appendingPathComponent("Applications/Whisp.app", isDirectory: true),
        ]
        let appSupportPath = applicationSupport.appendingPathComponent("Whisp", isDirectory: true)
        let preferencesPaths = [
            library.appendingPathComponent("Preferences/com.whisp.app.plist", isDirectory: false),
            library.appendingPathComponent("Caches/com.whisp.app", isDirectory: true),
            library.appendingPathComponent("Saved Application State/com.whisp.app.savedState", isDirectory: true),
        ]
        let whisperKitModelPaths = [
            documents.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true),
            documents.appendingPathComponent("huggingface/models/models/argmaxinc/whisperkit-coreml", isDirectory: true),
        ]
        let legacyStorePaths = [
            applicationSupport.appendingPathComponent("default.store", isDirectory: false),
            applicationSupport.appendingPathComponent("default.store-wal", isDirectory: false),
            applicationSupport.appendingPathComponent("default.store-shm", isDirectory: false),
        ]

        return [
            WhispUninstallItem(
                id: "applications",
                title: "Installed app bundle",
                detail: "Remove Whisp from the standard Applications folders.",
                action: .removePaths(applicationsPaths),
                isSelectedByDefault: true
            ),
            WhispUninstallItem(
                id: "appSupport",
                title: "App data and local model cache",
                detail: "Remove Application Support data, prompts, Python env, categories, and Hugging Face cache stored under Whisp.",
                action: .removePaths([appSupportPath]),
                isSelectedByDefault: true
            ),
            WhispUninstallItem(
                id: "preferences",
                title: "Preferences and cache files",
                detail: "Remove UserDefaults, app cache, and saved window state.",
                action: .clearPreferenceDomain(domain: appBundleIdentifier, paths: preferencesPaths),
                isSelectedByDefault: true
            ),
            WhispUninstallItem(
                id: "whisperKitModels",
                title: "Downloaded WhisperKit models",
                detail: "Remove WhisperKit model downloads stored in Documents.",
                action: .removePaths(whisperKitModelPaths),
                isSelectedByDefault: true
            ),
            WhispUninstallItem(
                id: "keychain",
                title: "Stored API keys",
                detail: "Delete OpenAI and Gemini API keys from the macOS keychain.",
                action: .removeKeychainItems(service: keychainService, accounts: keychainAccounts),
                isSelectedByDefault: true
            ),
            WhispUninstallItem(
                id: "privacy",
                title: "Privacy permissions",
                detail: "Reset Microphone, Accessibility, and Input Monitoring permissions for Whisp.",
                action: .resetPrivacyPermissions(bundleIdentifier: appBundleIdentifier, services: privacyServices),
                isSelectedByDefault: true
            ),
            WhispUninstallItem(
                id: "legacyStore",
                title: "Legacy transcription history database",
                detail: "Older builds stored history in a generic SwiftData file under Application Support/default.store. Leave this unchecked unless you want a full purge.",
                action: .removePaths(legacyStorePaths),
                isSelectedByDefault: false,
                requiresExplicitSelection: true
            ),
        ]
    }
}

public final class WhispUninstallerService {
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let processRunner: WhispProcessRunner

    public init(fileManager: FileManager = .default, userDefaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.processRunner = Self.runProcess
    }

    public init(
        fileManager: FileManager,
        userDefaults: UserDefaults,
        processRunner: @escaping WhispProcessRunner
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.processRunner = processRunner
    }

    public func uninstall(items: [WhispUninstallItem]) throws -> WhispUninstallRunResult {
        var removedPaths: [URL] = []
        var skippedPaths: [URL] = []
        var warnings: [String] = []

        for item in items {
            switch item.action {
            case .removePaths(let paths):
                try remove(paths: paths, removedPaths: &removedPaths, skippedPaths: &skippedPaths)
            case .clearPreferenceDomain(let domain, let paths):
                warnings.append(contentsOf: clearPreferenceDomain(domain))
                try remove(paths: paths, removedPaths: &removedPaths, skippedPaths: &skippedPaths)
            case .removeKeychainItems(let service, let accounts):
                try deleteKeychainItems(service: service, accounts: accounts)
            case .resetPrivacyPermissions(let bundleIdentifier, let services):
                warnings.append(contentsOf: resetPrivacyPermissions(bundleIdentifier: bundleIdentifier, services: services))
            }
        }

        return WhispUninstallRunResult(
            removedPaths: removedPaths,
            skippedPaths: skippedPaths,
            warnings: warnings
        )
    }

    private func remove(paths: [URL], removedPaths: inout [URL], skippedPaths: inout [URL]) throws {
        for path in paths {
            guard fileManager.fileExists(atPath: path.path) else {
                skippedPaths.append(path)
                continue
            }

            do {
                try fileManager.removeItem(at: path)
                removedPaths.append(path)
            } catch {
                throw WhispUninstallError.failedToRemove(path, underlying: error.localizedDescription)
            }
        }
    }

    private func deleteKeychainItems(service: String, accounts: [String]) throws {
        for account in accounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw WhispUninstallError.failedToDeleteKeychainItem(
                    service: service,
                    account: account,
                    status: status
                )
            }
        }
    }

    private func clearPreferenceDomain(_ domain: String) -> [String] {
        var warnings: [String] = []

        userDefaults.removePersistentDomain(forName: domain)
        userDefaults.synchronize()

        let (stdout, stderr, status) = processRunner("/usr/bin/defaults", ["delete", domain])
        if status != 0 {
            let detail = preferredProcessOutput(stdout: stdout, stderr: stderr)
            if !detail.localizedCaseInsensitiveContains("does not exist") {
                warnings.append("defaults delete \(domain) failed: \(detail)")
            }
        }

        return warnings
    }

    private func resetPrivacyPermissions(bundleIdentifier: String, services: [String]) -> [String] {
        var warnings: [String] = []

        for service in services {
            let (stdout, stderr, status) = processRunner("/usr/bin/tccutil", ["reset", service, bundleIdentifier])
            if status != 0 {
                let detail = preferredProcessOutput(stdout: stdout, stderr: stderr)
                warnings.append("tccutil reset \(service) failed: \(detail)")
            }
        }

        return warnings
    }

    @discardableResult
    private static func runProcess(_ executablePath: String, _ arguments: [String]) -> (String, String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return ("", String(describing: error), 1)
        }

        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }

    private func preferredProcessOutput(stdout: String, stderr: String) -> String {
        let trimmedError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            return trimmedError
        }

        let trimmedOutput = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOutput.isEmpty {
            return trimmedOutput
        }

        return "unknown error"
    }
}