import Foundation

enum CLIRunner {
    struct Output {
        var stdout: Data
        var stderr: String
        var status: Int32
    }

    static func run(_ executable: URL, arguments: [String], environment extra: [String: String]) async throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        // Apps launched from Finder get a bare PATH. npm-installed CLIs need `node`, which sits next to them.
        let path = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var environment = ["PATH": path.joined(separator: ":")]
        let inherited = ProcessInfo.processInfo.environment
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG"] {
            environment[key] = inherited[key]
        }
        environment.merge(extra) { _, new in new }
        process.environment = environment

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        let stdout: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { _ in
                    continuation.resume(returning: output.fileHandleForReading.readDataToEndOfFile())
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: AIError.launch(error.localizedDescription))
                }
            }
        } onCancel: {
            process.terminate()
        }
        let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Output(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }

    // An empty directory keeps the CLIs from picking up a project's instructions or git repo.
    static var workingDirectory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Voicer/cli-workdir", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func firstExecutable(_ candidates: [String]) -> URL? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Executables inside every nvm-managed Node version, newest first.
    static func nvmCandidates(_ name: String) -> [String] {
        let versions = home.appending(path: ".nvm/versions/node")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: versions.path)) ?? []
        return entries
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { versions.appending(path: "\($0)/bin/\(name)").path }
    }

    /// `~/.claude-team` → "Team", `~/.codex-side-project` → "Side project".
    static func friendlyName(directory: String, prefix: String) -> String {
        let name = URL(fileURLWithPath: directory).lastPathComponent
            .dropFirst(prefix.count)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static func directories(withPrefix prefix: String, containing file: String) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        return entries
            .filter { $0.hasPrefix(prefix) }
            .map { home.appending(path: $0).path }
            .filter { FileManager.default.fileExists(atPath: "\($0)/\(file)") }
            .sorted()
    }
}

enum AIError: LocalizedError {
    case notInstalled(String)
    case launch(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let tool): "\(tool) not found"
        case .launch(let message): "Couldn't start the CLI: \(message)"
        case .failed(let message): message
        }
    }
}
