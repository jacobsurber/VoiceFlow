import CryptoKit
import Foundation

internal enum UvError: Error, LocalizedError {
    case uvNotFound
    case uvTooOld(found: String, required: String)
    case uvInstallFailed(String)
    case pythonNotUsable(String)
    case venvCreationFailed(String)
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .uvNotFound:
            return
                "uv not found. Whisp could not find a managed copy of uv. Try setup again, or install it manually with: brew install uv"
        case .uvTooOld(let found, let required):
            return "uv version \(found) is too old; require \(required)+"
        case .uvInstallFailed(let msg):
            return
                "Whisp could not install uv automatically: \(msg)\n\nTry again with an internet connection, or install it manually with: brew install uv"
        case .pythonNotUsable(let msg):
            return "Python not usable: \(msg)"
        case .venvCreationFailed(let msg):
            return "Failed to create venv: \(msg)"
        case .syncFailed(let msg):
            return "Failed to sync Python deps: \(msg)"
        }
    }
}

internal struct UvBootstrap {
    static let minUvVersion = "0.8.5"
    static let defaultPythonVersion = "3.11"
    private static let managedUvVersion = "0.11.7"
    private static let systemExecutablePath = "/usr/bin:/bin:/usr/sbin:/sbin"

    private static var managedUvArchiveName: String {
        Arch.isAppleSilicon ? "uv-aarch64-apple-darwin.tar.gz" : "uv-x86_64-apple-darwin.tar.gz"
    }

    private static var managedUvArchiveRootName: String {
        managedUvArchiveName.replacingOccurrences(of: ".tar.gz", with: "")
    }

    private static var managedUvArchiveSHA256: String {
        Arch.isAppleSilicon
            ? "66e37d91f839e12481d7b932a1eccbfe732560f42c1cfb89faddfa2454534ba8"
            : "0a4bc8fcde4974ea3560be21772aeecab600a6f43fa6e58169f9fa7b3b71d302"
    }

    private static var managedUvDownloadURL: String {
        "https://github.com/astral-sh/uv/releases/download/\(managedUvVersion)/\(managedUvArchiveName)"
    }

    // Where we keep the app-managed project (contains pyproject + .venv)
    static func projectDir() throws -> URL {
        let fm = FileManager.default
        let appSupportBase = try applicationSupportBaseDirectory()
        let appSupport = appSupportBase.appendingPathComponent("Whisp", isDirectory: true)
        if !fm.fileExists(atPath: appSupport.path) {
            try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        let proj = appSupport.appendingPathComponent("python_project", isDirectory: true)
        if !fm.fileExists(atPath: proj.path) {
            try fm.createDirectory(at: proj, withIntermediateDirectories: true)
        }
        return proj
    }

    // Find uv or throw precise error (too old vs not found)
    static func findUv() throws -> URL {
        var foundButOld: (URL, String)? = nil
        // PATH
        if let pathUv = which("uv") {
            let url = URL(fileURLWithPath: pathUv)
            if let ver = try? uvVersion(at: url) {
                if isVersion(ver, greaterOrEqualThan: minUvVersion) { return url }
                foundButOld = (url, ver)
            }
        }
        // Bundled at bin/uv
        if let resURL = Bundle.main.resourceURL {
            let url = resURL.appendingPathComponent("bin/uv")
            if FileManager.default.isExecutableFile(atPath: url.path) {
                if let ver = try? uvVersion(at: url) {
                    if isVersion(ver, greaterOrEqualThan: minUvVersion) { return url }
                    foundButOld = foundButOld ?? (url, ver)
                }
            }
        }
        // Per-user tools dir
        if let toolsURL = try? applicationSupportBaseDirectory()
            .appendingPathComponent("Whisp/bin", isDirectory: true)
        {
            let url = toolsURL.appendingPathComponent("uv")
            if FileManager.default.isExecutableFile(atPath: url.path) {
                if let ver = try? uvVersion(at: url) {
                    if isVersion(ver, greaterOrEqualThan: minUvVersion) { return url }
                    foundButOld = foundButOld ?? (url, ver)
                }
            }
        }
        if let (_, ver) = foundButOld { throw UvError.uvTooOld(found: ver, required: minUvVersion) }
        throw UvError.uvNotFound
    }

    // Ensure project exists and dependencies are synced with uv. Returns path to project .venv python.
    // If userPython is nil, we let uv provision or use its managed interpreter (via --python 3.x)
    static func ensureVenv(userPython: String? = nil, log: ((String) -> Void)? = nil) throws -> URL {
        let uv = try ensureUv(log: log)
        let proj = try projectDir()

        let fm = FileManager.default
        // Copy pyproject.toml and uv.lock from bundle to project dir (if present / newer)
        try copyProjectFilesIfNeeded(to: proj)

        // Ensure .venv exists using specified Python (or default)
        let venvDir = proj.appendingPathComponent(".venv", isDirectory: true)
        if !fm.fileExists(atPath: venvDir.path) {
            let pythonSpecifier: String = (userPython?.isEmpty == false) ? userPython! : defaultPythonVersion
            log?("Creating project .venv with Python \(pythonSpecifier)…")
            let (out, err, status) = runInDir(uv.path, ["venv", "--python", pythonSpecifier], cwd: proj)
            if status != 0 { throw UvError.venvCreationFailed(err.isEmpty ? out : err) }
        }

        // Run uv sync in project directory. We do not enforce --frozen so that
        // a stale lock can be updated to match the bundled pyproject.toml.
        log?("Syncing project dependencies via uv sync…")
        let (out, err, status) = runInDir(uv.path, ["sync"], cwd: proj)
        if status != 0 { throw UvError.syncFailed(err.isEmpty ? out : err) }

        // Return the project venv python
        let candidates = [
            proj.appendingPathComponent(".venv/bin/python3").path,
            proj.appendingPathComponent(".venv/bin/python").path,
        ]
        for c in candidates where fm.isExecutableFile(atPath: c) { return URL(fileURLWithPath: c) }
        throw UvError.pythonNotUsable("project venv python not found")
    }

    // Copy pyproject.toml and uv.lock from bundle to per-user project dir
    private static func copyProjectFilesIfNeeded(to proj: URL) throws {
        guard let res = Bundle.main.resourceURL else { return }
        let fm = FileManager.default
        // Support both flattened and nested resource layouts for pyproject.toml only.
        // We intentionally do NOT copy a bundled uv.lock to avoid mismatches.
        let pyCandidates = [
            res.appendingPathComponent("pyproject.toml"),
            res.appendingPathComponent("Resources/pyproject.toml"),
        ]
        if let src = pyCandidates.first(where: { fm.fileExists(atPath: $0.path) }) {
            let dest = proj.appendingPathComponent("pyproject.toml")
            try copyIfDifferent(src: src, dst: dest)
        }
    }

    // MARK: - Utilities

    private static func ensureUv(log: ((String) -> Void)? = nil) throws -> URL {
        do {
            return try findUv()
        } catch let error as UvError {
            switch error {
            case .uvNotFound, .uvTooOld:
                return try installManagedUv(log: log)
            default:
                throw error
            }
        }
    }

    private static func installManagedUv(log: ((String) -> Void)? = nil) throws -> URL {
        let fm = FileManager.default
        let toolsDir = try applicationSupportBaseDirectory().appendingPathComponent(
            "Whisp/bin", isDirectory: true)
        if !fm.fileExists(atPath: toolsDir.path) {
            try fm.createDirectory(at: toolsDir, withIntermediateDirectories: true)
        }

        let tempDir = fm.temporaryDirectory.appendingPathComponent(
            "Whisp-uv-install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        do {
            let archiveURL = tempDir.appendingPathComponent(managedUvArchiveName)

            log?("Downloading uv...")
            try downloadManagedUvArchive(to: archiveURL)
            try verifyManagedUvArchive(at: archiveURL)

            log?("Installing uv...")
            try extractManagedUvArchive(at: archiveURL, into: tempDir)
            try installManagedUvExecutables(from: tempDir, to: toolsDir)

            let uvURL = toolsDir.appendingPathComponent("uv")
            guard fm.isExecutableFile(atPath: uvURL.path) else {
                throw UvError.uvInstallFailed(
                    "installer completed, but no executable uv was found in \(toolsDir.path)")
            }

            let version = try uvVersion(at: uvURL)
            guard isVersion(version, greaterOrEqualThan: minUvVersion) else {
                throw UvError.uvTooOld(found: version, required: minUvVersion)
            }
            return uvURL
        } catch let error as UvError {
            throw error
        } catch {
            throw UvError.uvInstallFailed(String(describing: error))
        }
    }

    private static func downloadManagedUvArchive(to archiveURL: URL) throws {
        let env = ProcessInfo.processInfo.environment
        if let overridePath = env["WHISP_UV_ARCHIVE_PATH"], !overridePath.isEmpty {
            let srcURL = URL(fileURLWithPath: overridePath)
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                try FileManager.default.removeItem(at: archiveURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: archiveURL)
            return
        }

        let (out, err, status) = run("/usr/bin/curl", ["-LsSf", managedUvDownloadURL, "-o", archiveURL.path])
        guard status == 0, FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw UvError.uvInstallFailed(preferredProcessOutput(stdout: out, stderr: err))
        }
    }

    private static func verifyManagedUvArchive(at archiveURL: URL) throws {
        let env = ProcessInfo.processInfo.environment
        let expectedDigest = (env["WHISP_UV_ARCHIVE_SHA256"] ?? managedUvArchiveSHA256)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let archiveData = try Data(contentsOf: archiveURL)
        let digest = SHA256.hash(data: archiveData)
            .map { String(format: "%02x", $0) }
            .joined()

        guard digest == expectedDigest else {
            throw UvError.uvInstallFailed("downloaded uv archive checksum mismatch")
        }
    }

    private static func extractManagedUvArchive(at archiveURL: URL, into directory: URL) throws {
        let (out, err, status) = runInDir("/usr/bin/tar", ["-xzf", archiveURL.path], cwd: directory)
        if status != 0 {
            throw UvError.uvInstallFailed(preferredProcessOutput(stdout: out, stderr: err))
        }
    }

    private static func installManagedUvExecutables(from tempDir: URL, to toolsDir: URL) throws {
        let fm = FileManager.default
        let extractedDir = tempDir.appendingPathComponent(managedUvArchiveRootName, isDirectory: true)

        for binaryName in ["uv", "uvx"] {
            let srcURL = extractedDir.appendingPathComponent(binaryName)
            let dstURL = toolsDir.appendingPathComponent(binaryName)
            guard fm.isExecutableFile(atPath: srcURL.path) else {
                throw UvError.uvInstallFailed("downloaded archive did not contain \(binaryName)")
            }
            if fm.fileExists(atPath: dstURL.path) {
                try fm.removeItem(at: dstURL)
            }
            try fm.copyItem(at: srcURL, to: dstURL)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstURL.path)
        }
    }

    private static func preferredProcessOutput(stdout: String, stderr: String) -> String {
        let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderrTrimmed.isEmpty { return stderrTrimmed }

        let stdoutTrimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdoutTrimmed.isEmpty { return stdoutTrimmed }

        return "unknown error"
    }

    private static func mergedProcessEnvironment(_ overrides: [String: String]? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let overrides {
            for (key, value) in overrides {
                env[key] = value
            }
        }
        env["PATH"] = normalizedExecutablePath(env["PATH"])
        return env
    }

    private static func normalizedExecutablePath(_ path: String?) -> String {
        var components = (path ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        for required in systemExecutablePath.split(separator: ":").map(String.init)
        where !components.contains(required) {
            components.append(required)
        }
        return components.joined(separator: ":")
    }

    private static func which(_ cmd: String) -> String? {
        let (out, _, status) = run("/usr/bin/which", [cmd])
        guard status == 0 else { return nil }
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    // Allow tests to override the base Application Support directory via env var
    private static func applicationSupportBaseDirectory() throws -> URL {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["WHISP_APP_SUPPORT_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return url
        }
        return try fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    private static func uvVersion(at url: URL) throws -> String {
        let (out, err, status) = run(url.path, ["--version"])
        guard status == 0 else { throw UvError.syncFailed(err.isEmpty ? out : err) }
        let s = out.trimmingCharacters(in: .whitespacesAndNewlines)
        // Common formats:
        //  - "uv 0.8.5 (ce3728681 2025-08-05)"
        //  - "uv 0.8.5"
        //  - "0.8.5"
        if let range = s.range(of: #"\d+\.\d+\.\d+([\-\+][A-Za-z0-9\.\-]+)?"#, options: .regularExpression) {
            return String(s[range])
        }
        let comps = s.split(separator: " ")
        if comps.count >= 2 && comps[0].lowercased() == "uv" { return String(comps[1]) }
        return s
    }

    private static func isVersion(_ v: String, greaterOrEqualThan min: String) -> Bool {
        func parse(_ s: String) -> [Int] { s.split(separator: ".").compactMap { Int($0) } }
        let a = parse(v)
        let b = parse(min)
        for i in 0..<max(a.count, b.count) {
            let ai = i < a.count ? a[i] : 0
            let bi = i < b.count ? b[i] : 0
            if ai != bi { return ai > bi }
        }
        return true
    }

    @discardableResult
    private static func run(_ cmd: String, _ args: [String], environment: [String: String]? = nil) -> (
        String, String, Int32
    ) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd)
        p.arguments = args
        p.environment = mergedProcessEnvironment(environment)
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch { return ("", String(describing: error), 1) }
        p.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (out, err, p.terminationStatus)
    }

    @discardableResult
    private static func runInDir(
        _ cmd: String, _ args: [String], cwd: URL, environment: [String: String]? = nil
    ) -> (String, String, Int32) {
        let p = Process()
        p.currentDirectoryURL = cwd
        p.executableURL = URL(fileURLWithPath: cmd)
        p.arguments = args
        p.environment = mergedProcessEnvironment(environment)
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch { return ("", String(describing: error), 1) }
        p.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (out, err, p.terminationStatus)
    }

    private static func copyIfDifferent(src: URL, dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            let srcData = try Data(contentsOf: src)
            let dstData = try Data(contentsOf: dst)
            if srcData == dstData { return }
            try fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
    }
}
