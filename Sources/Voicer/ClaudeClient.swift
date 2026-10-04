import Foundation

/// Runs Claude Code in print mode so requests use the user's subscription login.
struct ClaudeClient: TextRewriter {
    var executable: URL
    var configDirectory: String
    var model: String
    var effort: Effort

    static func accounts() -> [CLIAccount] {
        let home = CLIRunner.home.path
        var result: [CLIAccount] = []
        if FileManager.default.fileExists(atPath: "\(home)/.claude.json") {
            result.append(CLIAccount(directory: "", name: "Default", email: email(in: "\(home)/.claude.json")))
        }
        for dir in CLIRunner.directories(withPrefix: ".claude-", containing: ".claude.json") {
            result.append(CLIAccount(
                directory: dir,
                name: CLIRunner.friendlyName(directory: dir, prefix: ".claude-"),
                email: email(in: "\(dir)/.claude.json")
            ))
        }
        return result
    }

    private static func email(in file: String) -> String? {
        guard let data = FileManager.default.contents(atPath: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any]
        else { return nil }
        return account["emailAddress"] as? String
    }

    func complete(system: String, user: String) async throws -> String {
        let output = try await CLIRunner.run(
            executable,
            arguments: [
                "-p",
                "--model", model,
                "--effort", effort.rawValue,
                "--system-prompt", system,
                "--tools", "",
                "--strict-mcp-config",
                "--disable-slash-commands",
                "--no-session-persistence",
                "--setting-sources", "",
                "--output-format", "json",
                user,
            ],
            environment: configDirectory.isEmpty ? [:] : ["CLAUDE_CONFIG_DIR": configDirectory]
        )

        guard let result = try? JSONDecoder().decode(CLIResult.self, from: output.stdout) else {
            let detail = output.stderr.split(separator: "\n").last.map(String.init) ?? "exit code \(output.status)"
            throw AIError.failed("Claude: \(detail)")
        }
        let text = (result.result ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isError == true {
            throw AIError.failed("Claude: \(text.isEmpty ? "unknown error" : text)")
        }
        guard !text.isEmpty else { throw AIError.failed("Claude returned nothing") }
        return text
    }

    private struct CLIResult: Decodable {
        let result: String?
        let isError: Bool?

        enum CodingKeys: String, CodingKey {
            case result
            case isError = "is_error"
        }
    }
}
