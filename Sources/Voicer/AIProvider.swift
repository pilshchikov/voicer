import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var cliName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }

    var installHint: String {
        switch self {
        case .claude: "Install Claude Code and run `claude` once to log in."
        case .codex: "Install the Codex CLI (`npm i -g @openai/codex`) and run `codex login`."
        }
    }

    var efforts: [Effort] {
        switch self {
        case .claude: Effort.allCases
        case .codex: [.low, .medium, .high]
        }
    }

    func findExecutable() -> URL? {
        let home = CLIRunner.home.path
        switch self {
        case .claude:
            return CLIRunner.firstExecutable([
                "\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
                "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
            ] + CLIRunner.nvmCandidates("claude"))
        case .codex:
            return CLIRunner.firstExecutable([
                "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex",
            ] + CLIRunner.nvmCandidates("codex"))
        }
    }

    func accounts() -> [CLIAccount] {
        switch self {
        case .claude: ClaudeClient.accounts()
        case .codex: CodexClient.accounts()
        }
    }
}

enum Effort: String, CaseIterable, Identifiable {
    case low, medium, high, xhigh

    var id: String { rawValue }

    var title: String { self == .xhigh ? "Extra high" : rawValue.capitalized }
}

/// One CLI login. `directory` is empty for the CLI's default location.
struct CLIAccount: Identifiable, Hashable {
    var directory: String
    var name: String
    var email: String?

    var id: String { directory }
}

protocol TextRewriter {
    func complete(system: String, user: String) async throws -> String
}
