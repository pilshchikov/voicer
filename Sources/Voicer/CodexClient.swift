import Foundation

/// Runs `codex exec` read-only and ephemeral so requests use the user's ChatGPT login.
struct CodexClient: TextRewriter {
    var executable: URL
    var home: String
    var model: String
    var effort: Effort

    static func accounts() -> [CLIAccount] {
        let base = CLIRunner.home.path
        var result: [CLIAccount] = []
        if FileManager.default.fileExists(atPath: "\(base)/.codex/auth.json") {
            result.append(CLIAccount(directory: "", name: "Default", email: email(in: "\(base)/.codex/auth.json")))
        }
        for dir in CLIRunner.directories(withPrefix: ".codex-", containing: "auth.json") {
            result.append(CLIAccount(
                directory: dir,
                name: CLIRunner.friendlyName(directory: dir, prefix: ".codex-"),
                email: email(in: "\(dir)/auth.json")
            ))
        }
        return result
    }

    private static func email(in file: String) -> String? {
        guard let data = FileManager.default.contents(atPath: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String
        else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let decoded = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any]
        else { return nil }
        return claims["email"] as? String
    }

    func complete(system: String, user: String) async throws -> String {
        let outputFile = FileManager.default.temporaryDirectory.appending(path: "voicer-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outputFile) }

        var arguments = [
            "exec",
            "--skip-git-repo-check",
            "--ephemeral",
            "--ignore-user-config",
            "--ignore-rules",
            "-s", "read-only",
            "-C", CLIRunner.workingDirectory.path,
            "-c", "model_reasoning_effort=\"\(effort.rawValue)\"",
            "-o", outputFile.path,
        ]
        if !model.isEmpty {
            arguments += ["-m", model]
        }
        // Codex has no system prompt flag, so the instructions travel with the transcript.
        arguments.append("\(system)\n\n\(user)")

        let output = try await CLIRunner.run(
            executable,
            arguments: arguments,
            environment: home.isEmpty ? [:] : ["CODEX_HOME": home]
        )
        let text = (try? String(contentsOf: outputFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard output.status == 0, !text.isEmpty else {
            let detail = output.stderr.split(separator: "\n").last(where: { $0.lowercased().contains("error") })
                ?? output.stderr.split(separator: "\n").last
            throw AIError.failed("Codex: \(detail.map(String.init) ?? "exit code \(output.status)")")
        }
        return text
    }
}
