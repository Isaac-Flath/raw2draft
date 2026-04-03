import Foundation

/// Deploys bundled Claude Code context (skills, references, CLAUDE.md) to ~/.raw2draft/context/.
/// Called at app launch to ensure skills are always fresh from the app bundle.
enum ClaudeContextDeployer {
    /// Deployed context path that TerminalService passes via --add-dir.
    static let deployedPath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".raw2draft/context")

    /// Deploy bundled resources only if not already present (preserves user modifications).
    @discardableResult
    static func deploy() -> Bool {
        let fm = FileManager.default

        guard let bundledContext = Bundle.main.resourceURL?
            .appendingPathComponent("claude-context"),
              fm.fileExists(atPath: bundledContext.path) else { return false }

        // Only deploy if the context directory doesn't exist yet
        if fm.fileExists(atPath: deployedPath.path) {
            return true
        }

        try? fm.createDirectory(at: deployedPath.deletingLastPathComponent(),
                                withIntermediateDirectories: true)

        do {
            try fm.copyItem(at: bundledContext, to: deployedPath)
        } catch {
            return false
        }

        // Move skills/ → .claude/skills/ (Xcode strips hidden dirs from bundles)
        let bundledSkills = deployedPath.appendingPathComponent("skills")
        if fm.fileExists(atPath: bundledSkills.path) {
            let dotClaude = deployedPath.appendingPathComponent(".claude/skills")
            try? fm.createDirectory(at: dotClaude.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            try? fm.moveItem(at: bundledSkills, to: dotClaude)
        }

        return true
    }
}
