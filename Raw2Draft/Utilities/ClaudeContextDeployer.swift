import Foundation
import os

private let logger = Logger(subsystem: "com.raw2draft", category: "ContextDeployer")

/// Deploys Claude Code context to ~/.raw2draft/context/.
/// On first launch, copies the bundled CLAUDE.md and clones starter repos for skills and wiki.
/// Called at app launch to ensure context is available.
enum ClaudeContextDeployer {
    /// Deployed context path that TerminalService passes via --add-dir.
    static let deployedPath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".raw2draft/context")

    private static let versionFile = deployedPath.appendingPathComponent(".version")

    private static let starterSkillsRepo = "https://github.com/Isaac-Flath/agentkb-skills.git"
    private static let starterWikiRepo = "https://github.com/Isaac-Flath/agent-starter-wiki.git"

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

    /// Deploy bundled CLAUDE.md and clone starter repos if not already present.
    @discardableResult
    static func deploy() -> Bool {
        let fm = FileManager.default

        // If context directory already exists, just check staleness
        if fm.fileExists(atPath: deployedPath.path) {
            if isStale {
                logger.info("Deployed context is from a different build. Use Settings > Reset Context to update.")
            }
            return true
        }

        // Create the context directory
        do {
            try fm.createDirectory(at: deployedPath, withIntermediateDirectories: true)
        } catch {
            logger.warning("Failed to create context directory: \(error.localizedDescription)")
            return false
        }

        // Copy bundled CLAUDE.md
        if let bundledContext = Bundle.main.resourceURL?.appendingPathComponent("claude-context") {
            let bundledClaudeMd = bundledContext.appendingPathComponent("CLAUDE.md")
            if fm.fileExists(atPath: bundledClaudeMd.path) {
                let destClaudeMd = deployedPath.appendingPathComponent("CLAUDE.md")
                try? fm.copyItem(at: bundledClaudeMd, to: destClaudeMd)
            }
        }

        // Clone starter repos in the background
        cloneStarterRepos()

        // Stamp the version
        writeVersionStamp()

        return true
    }

    /// Clone starter skills and wiki repos into the context directory.
    private static func cloneStarterRepos() {
        let skillsPath = deployedPath.appendingPathComponent("skills")
        let wikiPath = deployedPath.appendingPathComponent("wiki")

        // Clone skills repo (contains .claude/skills/ structure)
        if !FileManager.default.fileExists(atPath: skillsPath.path) {
            gitClone(repo: starterSkillsRepo, to: skillsPath)
        }

        // Clone wiki repo (contains reference documents)
        if !FileManager.default.fileExists(atPath: wikiPath.path) {
            gitClone(repo: starterWikiRepo, to: wikiPath)
        }
    }

    /// Clone a git repo to a local path.
    private static func gitClone(repo: String, to localPath: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", repo, localPath.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                logger.info("Cloned \(repo) to \(localPath.path)")
            } else {
                logger.warning("Failed to clone \(repo) (exit code \(process.terminationStatus))")
            }
        } catch {
            logger.warning("Failed to clone \(repo): \(error.localizedDescription)")
        }
    }

    /// Replace deployed context with fresh copy.
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
