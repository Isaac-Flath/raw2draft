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
    func isClaudeInstalled() -> Bool
    func resolveClaudeBin() -> String
    func buildEnvironment(envFileService: EnvFileServiceProtocol) -> [String: String]
    func processParams(projectId: String, envFileService: EnvFileServiceProtocol, workingDirectory: URL) -> TerminalProcessParams
}

/// Resolves the Claude binary and builds process launch parameters.
final class TerminalService: TerminalServiceProtocol {
    private let fileManager = FileManager.default

    func isClaudeInstalled() -> Bool {
        Constants.claudeSearchPaths.contains { fileManager.fileExists(atPath: $0) }
    }

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

        // Add deployed context directory (bundled CLAUDE.md with app-level instructions)
        let contextPath = ClaudeContextDeployer.deployedPath
        if fileManager.fileExists(atPath: contextPath.path) {
            args += ["--add-dir", contextPath.path]
        }

        // Add skills directory (custom override or default clone)
        let skillsPath = ClaudeContextDeployer.skillsPath
        if fileManager.fileExists(atPath: skillsPath.path) {
            args += ["--add-dir", skillsPath.path]
        }

        // Add wiki directory (custom override or default clone)
        let wikiPath = ClaudeContextDeployer.wikiPath
        if fileManager.fileExists(atPath: wikiPath.path) {
            args += ["--add-dir", wikiPath.path]
        }

        return TerminalProcessParams(
            executable: claudeBin,
            args: args,
            environment: env,
            currentDirectory: workingDirectory.path
        )
    }
}
