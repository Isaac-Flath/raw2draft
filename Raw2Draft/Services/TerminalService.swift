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
    func isCodexInstalled() -> Bool
    func resolveCodexBin() -> String
    func buildEnvironment(envFileService: EnvFileServiceProtocol) -> [String: String]
    func processParams(projectId: String, envFileService: EnvFileServiceProtocol, workingDirectory: URL) -> TerminalProcessParams
}

/// Resolves the Codex binary and builds process launch parameters.
final class TerminalService: TerminalServiceProtocol {
    private let fileManager = FileManager.default

    func isCodexInstalled() -> Bool {
        Constants.codexSearchPaths.contains { fileManager.fileExists(atPath: $0) }
    }

    func resolveCodexBin() -> String {
        for path in Constants.codexSearchPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return "codex"
    }

    func buildEnvironment(envFileService: EnvFileServiceProtocol) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

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
        let codexBin = resolveCodexBin()
        var env = buildEnvironment(envFileService: envFileService)
        CodexContextDeployer.installCodexUserSkills()

        // Terminal type required for TUI apps like Codex.
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"

        var args = ["--dangerously-bypass-approvals-and-sandbox"]

        if let instructions = CodexContextDeployer.agentInstructions, !instructions.isEmpty {
            args += ["-c", "developer_instructions=\(tomlStringLiteral(instructions))"]
        }

        args += ["-c", "skills.include_instructions=true"]

        // Grant Codex access to the editable Raw2Draft context directories.
        let contextPath = CodexContextDeployer.deployedPath
        if fileManager.fileExists(atPath: contextPath.path) {
            args += ["--add-dir", contextPath.path]
        }

        // Add skills directory (custom override or default clone)
        let skillsPath = CodexContextDeployer.skillsPath
        if fileManager.fileExists(atPath: skillsPath.path) {
            args += ["--add-dir", skillsPath.path]
        }

        // Add wiki directory (custom override or default clone)
        let wikiPath = CodexContextDeployer.wikiPath
        if fileManager.fileExists(atPath: wikiPath.path) {
            args += ["--add-dir", wikiPath.path]
        }

        return TerminalProcessParams(
            executable: codexBin,
            args: args,
            environment: env,
            currentDirectory: workingDirectory.path
        )
    }

    private func tomlStringLiteral(_ value: String) -> String {
        var escaped = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34:
                escaped += "\\\""
            case 92:
                escaped += "\\\\"
            case 10:
                escaped += "\\n"
            case 13:
                escaped += "\\r"
            case 9:
                escaped += "\\t"
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        escaped += "\""
        return escaped
    }
}
