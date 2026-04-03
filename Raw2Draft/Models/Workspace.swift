import Foundation

/// The app's workspace mode determines what UI is shown and how services are configured.
enum WorkspaceMode: Equatable {
    /// A generic directory with file tree sidebar.
    case directory(URL)

    /// The content-platform monorepo (full content studio UI).
    case contentStudio(URL)

    /// The root URL for the workspace.
    var rootURL: URL {
        switch self {
        case .directory(let url): return url
        case .contentStudio(let url): return url
        }
    }

    /// Display label for the title bar.
    var label: String {
        rootURL.lastPathComponent
    }

    /// Whether this is the content studio mode with full pipeline UI.
    var isContentStudio: Bool {
        if case .contentStudio = self { return true }
        return false
    }

    // MARK: - Content Studio Paths (only meaningful in .contentStudio)

    var projectsDirectory: URL? {
        guard case .contentStudio(let root) = self else { return nil }
        return root.appendingPathComponent("projects")
    }

    var postsDirectory: URL? {
        guard case .contentStudio(let root) = self else { return nil }
        return root.appendingPathComponent("posts")
    }

    var envFilePath: URL? {
        guard case .contentStudio(let root) = self else { return nil }
        return root.appendingPathComponent(".env")
    }

    var skillsDirectory: URL? {
        guard case .contentStudio(let root) = self else { return nil }
        return root.appendingPathComponent(".claude/skills")
    }

    // MARK: - Detection

    /// Result of detecting workspace mode from a URL.
    struct DetectionResult: Equatable {
        let mode: WorkspaceMode
        /// If the user opened a specific file, this is the file to auto-open in the editor.
        let initialFile: URL?
    }

    /// Detect the appropriate mode for opening a URL.
    static func detect(url: URL) -> DetectionResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            // File doesn't exist — open parent directory
            return DetectionResult(mode: .directory(url.deletingLastPathComponent()), initialFile: nil)
        }

        if !isDir.boolValue {
            // It's a file — open its parent directory with this file pre-selected
            let parentDir = url.deletingLastPathComponent()

            // Check if parent is a content root (has posts/ and projects/ directories)
            let hasPosts = fm.fileExists(atPath: parentDir.appendingPathComponent("posts").path)
            let hasProjects = fm.fileExists(atPath: parentDir.appendingPathComponent("projects").path)

            if hasPosts && hasProjects {
                return DetectionResult(mode: .contentStudio(parentDir), initialFile: url)
            }

            return DetectionResult(mode: .directory(parentDir), initialFile: url)
        }

        // It's a directory — detect content studio if it has posts/ and projects/
        let hasPosts = fm.fileExists(atPath: url.appendingPathComponent("posts").path)
        let hasProjects = fm.fileExists(atPath: url.appendingPathComponent("projects").path)

        if hasPosts && hasProjects {
            return DetectionResult(mode: .contentStudio(url), initialFile: nil)
        }

        return DetectionResult(mode: .directory(url), initialFile: nil)
    }
}
