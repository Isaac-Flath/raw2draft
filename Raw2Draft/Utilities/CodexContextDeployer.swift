import Foundation
import os

private let logger = Logger(subsystem: "com.raw2draft", category: "ContextDeployer")

/// Deploys Codex context to ~/.raw2draft/context/.
/// On first launch, copies the bundled AGENTS.md and clones starter repos for skills and wiki.
/// Called at app launch to ensure context is available.
enum CodexContextDeployer {
    /// Deployed context path that TerminalService exposes to Codex.
    static let deployedPath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".raw2draft/context")

    private static let versionFile = deployedPath.appendingPathComponent(".version")
    static let agentInstructionsPath: URL = deployedPath.appendingPathComponent("AGENTS.md")

    private static let starterSkillsRepo = "https://github.com/Isaac-Flath/agent-starter-skills.git"
    private static let starterWikiRepo = "https://github.com/Isaac-Flath/agent-starter-wiki.git"

    /// The default (cloned) skills path inside the deployed context directory.
    static let defaultSkillsPath: URL = deployedPath.appendingPathComponent("skills")

    /// Codex's user-level skill root. Raw2Draft-managed skills are copied here for native discovery.
    static let codexUserSkillsPath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/skills")

    /// The default (cloned) wiki path inside the deployed context directory.
    static let defaultWikiPath: URL = deployedPath.appendingPathComponent("wiki")

    /// Resolved skills path: custom override if set, otherwise the default clone.
    static var skillsPath: URL {
        if let custom = UserDefaults.standard.string(forKey: UserDefaultsKey.customSkillsPath),
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        return defaultSkillsPath
    }

    /// Resolved wiki path: custom override if set, otherwise the default clone.
    static var wikiPath: URL {
        if let custom = UserDefaults.standard.string(forKey: UserDefaultsKey.customWikiPath),
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        return defaultWikiPath
    }

    /// Skill roots that should be visible to Codex.
    static var codexSkillRoots: [URL] {
        return findSkillRootDirs(under: skillsPath)
    }

    /// Individual SKILL.md files that Codex should enable for Raw2Draft sessions.
    static var codexSkillFiles: [URL] {
        codexSkillRoots.flatMap(skillFiles(in:))
    }

    /// App-level instructions injected into Codex sessions.
    static var agentInstructions: String? {
        try? String(contentsOf: agentInstructionsPath, encoding: .utf8)
    }

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

    /// Deploy bundled AGENTS.md and clone starter repos if not already present.
    @discardableResult
    static func deploy() -> Bool {
        let fm = FileManager.default
        var createdContext = false

        if fm.fileExists(atPath: deployedPath.path) {
            if isStale {
                logger.info("Deployed context is from a different build. Use Settings > Reset Context to update.")
            }
        } else {
            // Create the context directory
            do {
                try fm.createDirectory(at: deployedPath, withIntermediateDirectories: true)
            } catch {
                logger.warning("Failed to create context directory: \(error.localizedDescription)")
                return false
            }
            createdContext = true
        }

        copyBundledAgentInstructionsIfNeeded()
        if createdContext || deployedVersion == nil {
            writeVersionStamp()
        }

        // Clone starter repos if missing (idempotent — checks each sub-dir)
        cloneStarterRepos()
        copyBundledDefaultsIfNeeded()
        installCodexUserSkills()

        return true
    }

    /// Clone starter skills and wiki repos into the context directory.
    /// Skips repos that have a custom path configured in Settings.
    private static func cloneStarterRepos() {
        let defaults = UserDefaults.standard
        let fm = FileManager.default

        // Skip skills clone if a custom path is configured
        let hasCustomSkills = !(defaults.string(forKey: UserDefaultsKey.customSkillsPath) ?? "").isEmpty
        if !hasCustomSkills && !fm.fileExists(atPath: defaultSkillsPath.path) {
            gitClone(repo: starterSkillsRepo, to: defaultSkillsPath)
        }

        // Skip wiki clone if a custom path is configured
        let hasCustomWiki = !(defaults.string(forKey: UserDefaultsKey.customWikiPath) ?? "").isEmpty
        if !hasCustomWiki && !fm.fileExists(atPath: defaultWikiPath.path) {
            gitClone(repo: starterWikiRepo, to: defaultWikiPath)
        }
    }

    /// Find all skill-root directories Codex should scan.
    /// Supports Codex `.agents/skills` and direct skill-root overrides.
    static func findSkillRootDirs(under base: URL) -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        func appendCodexLayout(for repo: URL) {
            let codex = repo.appendingPathComponent(".agents/skills")
            if fm.fileExists(atPath: codex.path), containsSkillDirectories(at: codex) {
                results.append(codex)
            }
        }

        if isSkillDir(base) || containsSkillDirectories(at: base) {
            results.append(base)
        }

        appendCodexLayout(for: base)

        if let children = try? fm.contentsOfDirectory(atPath: base.path) {
            for child in children where !child.hasPrefix(".") {
                let repo = base.appendingPathComponent(child)
                appendCodexLayout(for: repo)
            }
        }

        var seen = Set<String>()
        return results.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func isSkillDir(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("SKILL.md").path)
    }

    private static func containsSkillDirectories(at url: URL) -> Bool {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(atPath: url.path) else { return false }

        return children.contains { child in
            isSkillDir(url.appendingPathComponent(child))
        }
    }

    private static func skillFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        let direct = root.appendingPathComponent("SKILL.md")
        if fm.fileExists(atPath: direct.path) {
            return [direct]
        }

        guard let children = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }

        return children.sorted().compactMap { child in
            let skillFile = root
                .appendingPathComponent(child)
                .appendingPathComponent("SKILL.md")
            return fm.fileExists(atPath: skillFile.path) ? skillFile : nil
        }
    }

    private static func copyBundledAgentInstructionsIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: agentInstructionsPath.path),
              let bundledContext = Bundle.main.resourceURL?.appendingPathComponent("codex-context") else {
            return
        }

        let bundledAgentsMd = bundledContext.appendingPathComponent("AGENTS.md")
        if fm.fileExists(atPath: bundledAgentsMd.path) {
            try? fm.copyItem(at: bundledAgentsMd, to: agentInstructionsPath)
        }
    }

    private static func copyBundledDefaultsIfNeeded() {
        guard let bundledContext = Bundle.main.resourceURL?.appendingPathComponent("codex-context") else {
            return
        }

        copyBundledDirectoryIfNeeded(
            from: bundledContext.appendingPathComponent("skills"),
            to: defaultSkillsPath,
            isMissingContent: codexSkillFiles.isEmpty
        )
        copyBundledDirectoryIfNeeded(
            from: bundledContext.appendingPathComponent("wiki"),
            to: defaultWikiPath,
            isMissingContent: !FileManager.default.fileExists(
                atPath: defaultWikiPath.appendingPathComponent("writing-with-zinsser.md").path
            )
        )
    }

    private static func copyBundledDirectoryIfNeeded(from source: URL, to destination: URL, isMissingContent: Bool) {
        let fm = FileManager.default
        guard isMissingContent, fm.fileExists(atPath: source.path) else { return }

        do {
            if !fm.fileExists(atPath: destination.path) {
                try fm.copyItem(at: source, to: destination)
                return
            }

            let entries = (try? fm.contentsOfDirectory(atPath: source.path)) ?? []
            for entry in entries where !entry.hasPrefix(".") {
                let sourceEntry = source.appendingPathComponent(entry)
                let destinationEntry = destination.appendingPathComponent(entry)
                if !fm.fileExists(atPath: destinationEntry.path) {
                    try fm.copyItem(at: sourceEntry, to: destinationEntry)
                }
            }
        } catch {
            logger.warning("Failed to copy bundled context defaults: \(error.localizedDescription)")
        }
    }

    /// Copy configured Raw2Draft skills into Codex's user skill root so Codex discovers them natively.
    static func installCodexUserSkills() {
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: codexUserSkillsPath, withIntermediateDirectories: true)

            for skillFile in codexSkillFiles {
                let sourceDir = skillFile.deletingLastPathComponent()
                let destinationDir = codexUserSkillsPath.appendingPathComponent(sourceDir.lastPathComponent)
                let marker = destinationDir.appendingPathComponent(".raw2draft-managed")

                if fm.fileExists(atPath: destinationDir.path) {
                    guard fm.fileExists(atPath: marker.path) else {
                        logger.info("Skipping unmanaged Codex skill at \(destinationDir.path)")
                        continue
                    }
                    try fm.removeItem(at: destinationDir)
                }

                try fm.copyItem(at: sourceDir, to: destinationDir)
                try "managed by Raw2Draft\n".write(to: marker, atomically: true, encoding: .utf8)
            }
        } catch {
            logger.warning("Failed to install Raw2Draft Codex skills: \(error.localizedDescription)")
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
