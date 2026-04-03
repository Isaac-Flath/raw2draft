import Foundation

/// Parameters for launching a terminal process.
struct TerminalProcessParams {
    let executable: String
    let args: [String]
    let environment: [String: String]
    let currentDirectory: String
}

/// Protocol for terminal session management.
protocol TerminalServiceProtocol {
    func resolveClaudeBin() -> String
    func buildEnvironment(envFileService: EnvFileServiceProtocol) -> [String: String]
    func processParams(projectId: String, envFileService: EnvFileServiceProtocol, workingDirectory: URL) -> TerminalProcessParams
}

/// Resolves the Claude binary and builds process launch parameters.
final class TerminalService: TerminalServiceProtocol {
    private let fileManager = FileManager.default

    func resolveClaudeBin() -> String {
        for path in Constants.claudeSearchPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return "claude"
    }

    func buildEnvironment(envFileService: EnvFileServiceProtocol) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // Remove Claude Code nesting guard so the app can launch claude as a child
        env.removeValue(forKey: "CLAUDECODE")

        let extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin",
        ]
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        let newPaths = extraPaths.filter { fileManager.fileExists(atPath: $0) }
        env["PATH"] = (newPaths + [existingPath]).joined(separator: ":")

        envFileService.hydrateEnvironment(&env)

        return env
    }

    func processParams(projectId: String, envFileService: EnvFileServiceProtocol, workingDirectory: URL) -> TerminalProcessParams {
        let claudeBin = resolveClaudeBin()
        var env = buildEnvironment(envFileService: envFileService)

        // Terminal type — required for TUI apps like Claude Code
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"

        // Enable CLAUDE.md loading from --add-dir directories
        env["CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD"] = "1"

        var args = ["--dangerously-skip-permissions"]

        // Add deployed context directory (deployed at app launch by ClaudeContextDeployer)
        let contextPath = ClaudeContextDeployer.deployedPath.path
        if fileManager.fileExists(atPath: contextPath) {
            args += ["--add-dir", contextPath]
        }

        return TerminalProcessParams(
            executable: claudeBin,
            args: args,
            environment: env,
            currentDirectory: workingDirectory.path
        )
    }
}
