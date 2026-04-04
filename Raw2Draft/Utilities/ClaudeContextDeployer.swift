import Foundation
import os

private let logger = Logger(subsystem: "com.raw2draft", category: "ContextDeployer")

/// Deploys bundled Claude Code context (skills, references, CLAUDE.md) to ~/.raw2draft/context/.
/// Called at app launch to ensure skills are available.
enum ClaudeContextDeployer {
    /// Deployed context path that TerminalService passes via --add-dir.
    static let deployedPath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".raw2draft/context")

    private static let versionFile = deployedPath.appendingPathComponent(".version")

    /// Whether the deployed context is older than the bundled version.
    static var isStale: Bool {
        guard let deployed = deployedVersion, let bundled = bundledVersion else { return false }
        return deployed != bundled
    }

    /// The build number stamped into the deployed context, if any.
    static var deployedVersion: String? {
        try? String(contentsOf: versionFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The current app build number.
    static var bundledVersion: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    /// Deploy bundled resources only if not already present (preserves user modifications).
    @discardableResult
    static func deploy() -> Bool {
        let fm = FileManager.default

        guard let bundledContext = Bundle.main.resourceURL?
            .appendingPathComponent("claude-context"),
              fm.fileExists(atPath: bundledContext.path) else { return false }

        // Only deploy if the context directory doesn't exist yet
        if fm.fileExists(atPath: deployedPath.path) {
            if isStale {
                logger.info("Deployed context is from a different build. Use Settings > Reset Context to update.")
            }
            return true
        }

        try? fm.createDirectory(at: deployedPath.deletingLastPathComponent(),
                                withIntermediateDirectories: true)

        do {
            try fm.copyItem(at: bundledContext, to: deployedPath)
        } catch {
            logger.warning("Failed to deploy context: \(error.localizedDescription)")
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

        // Stamp the version so we can detect staleness later
        writeVersionStamp()

        return true
    }

    /// Replace deployed context with fresh copy from the app bundle.
    /// Returns true on success.
    @discardableResult
    static func resetToDefaults() -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: deployedPath.path) {
            do {
                try fm.removeItem(at: deployedPath)
            } catch {
                logger.warning("Failed to remove existing context: \(error.localizedDescription)")
                return false
            }
        }
        return deploy()
    }

    private static func writeVersionStamp() {
        guard let version = bundledVersion else { return }
        try? version.write(to: versionFile, atomically: true, encoding: .utf8)
    }
}
