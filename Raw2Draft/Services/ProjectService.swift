import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "com.raw2draft", category: "ProjectService")

/// Protocol for project file system operations.
protocol ProjectServiceProtocol {
    func listProjects() throws -> [String]
    func createProject(name: String) throws -> String
    func deleteProject(projectId: String) throws
    func duplicateProject(projectId: String) throws -> String
    func renameProject(projectId: String, newName: String) throws -> String
    func listProjectFiles(projectId: String) throws -> [ProjectFile]
    func listAllProjectFiles(projectId: String) throws -> [String: [ProjectFile]]
    func readProjectFile(projectId: String, relativePath: String) throws -> String
    func writeProjectFile(projectId: String, relativePath: String, content: String) throws
    func uploadSourceFile(projectId: String, filename: String, data: Data) throws -> String
    func getProjectStatus(projectId: String) throws -> Project
    func listProjectStatuses() throws -> [Project]
    func getSourceUrls(projectId: String) throws -> SourcesFile
    func addSourceUrl(projectId: String, url: String, type: URLType) throws -> SourcesFile
    func removeSourceUrl(projectId: String, url: String) throws -> SourcesFile
    func updateSourceUrlStatus(projectId: String, url: String, status: URLStatus) throws -> SourcesFile
    func fileExists(projectId: String, relativePath: String) -> Bool
    func resolveProjectRoot(_ projectId: String) -> URL
    func revealInFinder(projectId: String)
    func bootstrapSkillsIfNeeded()
}

/// File system-based project CRUD operations. Port of server/projects.js.
final class ProjectService: ProjectServiceProtocol {
    private let fileManager = FileManager.default
    private let projectsDirectory: URL

    private let jsonEncoder = JSONCoders.encoder
    private let jsonDecoder = JSONCoders.decoder

    init(projectsDirectory: URL = Constants.defaultContentPlatformRoot.appendingPathComponent("posts")) {
        self.projectsDirectory = projectsDirectory
        try? fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
    }

    /// Verify skills directory exists at the monorepo root.
    func bootstrapSkillsIfNeeded() {
        let skillsDir = projectsDirectory.deletingLastPathComponent().appendingPathComponent(".claude/skills")
        if !fileManager.fileExists(atPath: skillsDir.path) {
            logger.warning("Skills directory not found at \(skillsDir.path)")
        }
    }

    // MARK: - Path Resolution

    func resolveProjectRoot(_ projectId: String) -> URL {
        projectsDirectory.appendingPathComponent(projectId)
    }

    private func resolveSafe(projectRoot: URL, relativePath: String) throws -> URL {
        guard let resolved = PathSanitizer.resolveSafe(root: projectRoot, relativePath: relativePath) else {
            throw ProjectServiceError.invalidPath
        }
        return resolved
    }

    // MARK: - Project CRUD

    func listProjects() throws -> [String] {
        guard fileManager.fileExists(atPath: projectsDirectory.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { url in
                var isDir: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
            .map { $0.lastPathComponent }
            .sorted()
    }

    func createProject(name: String) throws -> String {
        guard let slug = PathSanitizer.slugify(name) else {
            throw ProjectServiceError.invalidProjectName
        }

        let projectId = "\(Constants.projectDateString())_\(slug)"
        let projectRoot = resolveProjectRoot(projectId)

        guard !fileManager.fileExists(atPath: projectRoot.path) else {
            throw ProjectServiceError.projectAlreadyExists
        }

        try fileManager.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        for subdir in Constants.projectSubdirs {
            try fileManager.createDirectory(
                at: projectRoot.appendingPathComponent(subdir),
                withIntermediateDirectories: true
            )
        }

        return projectId
    }

    // MARK: - Project Management

    func deleteProject(projectId: String) throws {
        let projectRoot = resolveProjectRoot(projectId)
        guard fileManager.fileExists(atPath: projectRoot.path) else {
            throw ProjectServiceError.projectNotFound
        }
        try fileManager.removeItem(at: projectRoot)
    }

    func duplicateProject(projectId: String) throws -> String {
        let projectRoot = resolveProjectRoot(projectId)
        guard fileManager.fileExists(atPath: projectRoot.path) else {
            throw ProjectServiceError.projectNotFound
        }

        // Create new project ID with "-copy" suffix
        var newId = "\(projectId)-copy"
        var counter = 2
        while fileManager.fileExists(atPath: resolveProjectRoot(newId).path) {
            newId = "\(projectId)-copy-\(counter)"
            counter += 1
        }

        let newRoot = resolveProjectRoot(newId)
        try fileManager.copyItem(at: projectRoot, to: newRoot)

        return newId
    }

    func renameProject(projectId: String, newName: String) throws -> String {
        let projectRoot = resolveProjectRoot(projectId)
        guard fileManager.fileExists(atPath: projectRoot.path) else {
            throw ProjectServiceError.projectNotFound
        }

        guard let slug = PathSanitizer.slugify(newName) else {
            throw ProjectServiceError.invalidProjectName
        }

        // Preserve the date prefix, replace the slug
        let newId: String
        if let prefix = Project.datePrefix(from: projectId) {
            newId = "\(prefix)_\(slug)"
        } else {
            newId = "\(Constants.projectDateString())_\(slug)"
        }

        let newRoot = resolveProjectRoot(newId)
        guard !fileManager.fileExists(atPath: newRoot.path) else {
            throw ProjectServiceError.projectAlreadyExists
        }

        try fileManager.moveItem(at: projectRoot, to: newRoot)
        return newId
    }

    func revealInFinder(projectId: String) {
        let projectRoot = resolveProjectRoot(projectId)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: projectRoot.path)
    }

    // MARK: - File Operations

    func listProjectFiles(projectId: String) throws -> [ProjectFile] {
        let projectRoot = resolveProjectRoot(projectId)
        var files: [ProjectFile] = []

        // Collect all source files in a single scan, partitioned into video vs non-video
        let sourceFiles = collectFiles(
            in: projectRoot.appendingPathComponent("source"),
            prefix: "source",
            group: .source
        )
        for file in sourceFiles {
            let ext = (file.name as NSString).pathExtension.lowercased()
            if Constants.videoExtensions.contains(ext) {
                files.append(ProjectFile(path: file.path, name: file.name, group: .video, size: file.size, modified: file.modified))
            } else {
                files.append(file)
            }
        }

        // Collect videos from video/out/
        files += collectFiles(
            in: projectRoot.appendingPathComponent("video/out"),
            prefix: "video/out",
            filter: { Constants.videoExtensions.contains(($0 as NSString).pathExtension.lowercased()) },
            group: .video
        )

        // Collect content files
        files += collectFiles(
            in: projectRoot.appendingPathComponent("content"),
            prefix: "content",
            group: .content
        )

        // Collect social files (excluding .py)
        files += collectFiles(
            in: projectRoot.appendingPathComponent("social"),
            prefix: "social",
            filter: { ($0 as NSString).pathExtension.lowercased() != "py" },
            group: .social
        )

        // Collect images
        files += collectFiles(
            in: projectRoot.appendingPathComponent("images"),
            prefix: "images",
            filter: { Constants.imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) },
            group: .images
        )

        // Collect screenshots
        files += collectFiles(
            in: projectRoot.appendingPathComponent("screenshots"),
            prefix: "screenshots",
            filter: { Constants.imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) },
            group: .screenshots
        )

        return files
    }

    func listAllProjectFiles(projectId: String) throws -> [String: [ProjectFile]] {
        let projectRoot = resolveProjectRoot(projectId)
        var result: [String: [ProjectFile]] = [:]

        for dir in Constants.projectSubdirs {
            let dirURL = projectRoot.appendingPathComponent(dir)
            guard fileManager.fileExists(atPath: dirURL.path) else { continue }

            let contents = try fileManager.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let files: [ProjectFile] = contents.compactMap { url in
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
                      !isDir.boolValue else { return nil }

                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return ProjectFile(
                    path: "\(dir)/\(url.lastPathComponent)",
                    name: url.lastPathComponent,
                    group: FileGroup(rawValue: dir) ?? .source,
                    size: values?.fileSize,
                    modified: values?.contentModificationDate
                )
            }

            if !files.isEmpty {
                result[dir] = files
            }
        }

        return result
    }

    func readProjectFile(projectId: String, relativePath: String) throws -> String {
        let projectRoot = resolveProjectRoot(projectId)
        let resolved = try resolveSafe(projectRoot: projectRoot, relativePath: relativePath)

        guard fileManager.fileExists(atPath: resolved.path) else {
            throw ProjectServiceError.fileNotFound(relativePath)
        }

        return try String(contentsOf: resolved, encoding: .utf8)
    }

    func writeProjectFile(projectId: String, relativePath: String, content: String) throws {
        let projectRoot = resolveProjectRoot(projectId)
        let resolved = try resolveSafe(projectRoot: projectRoot, relativePath: relativePath)

        // Ensure parent directory exists
        try fileManager.createDirectory(
            at: resolved.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try content.write(to: resolved, atomically: true, encoding: .utf8)
    }

    func uploadSourceFile(projectId: String, filename: String, data: Data) throws -> String {
        let projectRoot = resolveProjectRoot(projectId)
        guard fileManager.fileExists(atPath: projectRoot.path) else {
            throw ProjectServiceError.projectNotFound
        }

        guard let sanitized = PathSanitizer.sanitizeFilename(filename) else {
            throw ProjectServiceError.invalidFilename
        }

        let sourceDir = projectRoot.appendingPathComponent("source")
        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let filePath = sourceDir.appendingPathComponent(sanitized)
        try data.write(to: filePath)

        return "source/\(sanitized)"
    }

    func fileExists(projectId: String, relativePath: String) -> Bool {
        let projectRoot = resolveProjectRoot(projectId)
        guard let resolved = PathSanitizer.resolveSafe(root: projectRoot, relativePath: relativePath) else {
            return false
        }
        return fileManager.fileExists(atPath: resolved.path)
    }

    // MARK: - Project Status

    func getProjectStatus(projectId: String) throws -> Project {
        let projectRoot = resolveProjectRoot(projectId)
        let socialDir = projectRoot.appendingPathComponent("social")
        let sourceDir = projectRoot.appendingPathComponent("source")
        let videoDir = projectRoot.appendingPathComponent("video")

        let hasSource = dirContains(sourceDir, matching: {
            Constants.markdownExtensions.contains($0.pathExtension.lowercased())
        }) || dirContains(sourceDir)
        let hasVideo = dirContains(videoDir)
        let hasBlog = fileExists(projectId: projectId, relativePath: "blog.md")
            || fileExists(projectId: projectId, relativePath: "blog.ipynb")
        let hasSocial = dirContains(socialDir, matching: {
            Constants.markdownExtensions.contains($0.pathExtension.lowercased())
        })
        let published = fileExists(projectId: projectId, relativePath: "published.json")
            || fileExists(projectId: projectId, relativePath: "published.md")
            || fileExists(projectId: projectId, relativePath: "published.txt")
            || fileExists(projectId: projectId, relativePath: ".published")

        let stage: ProjectStage
        if published { stage = .published }
        else if hasSocial { stage = .social }
        else if hasBlog { stage = .blog }
        else if hasVideo { stage = .video }
        else if hasSource { stage = .source }
        else { stage = .empty }

        return Project(
            id: projectId,
            path: projectRoot,
            hasSource: hasSource,
            hasVideo: hasVideo,
            hasBlog: hasBlog,
            hasSocial: hasSocial,
            published: published,
            stage: stage
        )
    }

    func listProjectStatuses() throws -> [Project] {
        try listProjects().map { try getProjectStatus(projectId: $0) }
    }

    // MARK: - Source URLs

    func getSourceUrls(projectId: String) throws -> SourcesFile {
        let projectRoot = resolveProjectRoot(projectId)
        let sourcesPath = projectRoot.appendingPathComponent("source/sources.json")

        guard fileManager.fileExists(atPath: sourcesPath.path) else {
            return SourcesFile(urls: [])
        }

        do {
            let data = try Data(contentsOf: sourcesPath)
            return try jsonDecoder.decode(SourcesFile.self, from: data)
        } catch {
            return SourcesFile(urls: [])
        }
    }

    func addSourceUrl(projectId: String, url: String, type: URLType = .unknown) throws -> SourcesFile {
        let projectRoot = resolveProjectRoot(projectId)
        guard fileManager.fileExists(atPath: projectRoot.path) else {
            throw ProjectServiceError.projectNotFound
        }

        let sourceDir = projectRoot.appendingPathComponent("source")
        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        var sources = try getSourceUrls(projectId: projectId)

        // Detect URL type
        let detectedType: URLType
        if type == .unknown {
            if url.contains("youtube.com") || url.contains("youtu.be") {
                detectedType = .youtube
            } else if url.hasSuffix(".pdf") {
                detectedType = .pdf
            } else {
                detectedType = .webpage
            }
        } else {
            detectedType = type
        }

        sources.urls.append(SourceURL(
            url: url,
            type: detectedType,
            status: .pending,
            addedAt: Date()
        ))

        try writeSourcesFile(projectId: projectId, sources: sources)
        return sources
    }

    func removeSourceUrl(projectId: String, url: String) throws -> SourcesFile {
        var sources = try getSourceUrls(projectId: projectId)
        sources.urls.removeAll { $0.url == url }
        try writeSourcesFile(projectId: projectId, sources: sources)
        return sources
    }

    func updateSourceUrlStatus(projectId: String, url: String, status: URLStatus) throws -> SourcesFile {
        var sources = try getSourceUrls(projectId: projectId)
        guard let index = sources.urls.firstIndex(where: { $0.url == url }) else {
            throw ProjectServiceError.urlNotFound
        }

        sources.urls[index].status = status
        sources.urls[index].updatedAt = Date()
        try writeSourcesFile(projectId: projectId, sources: sources)
        return sources
    }

    // MARK: - Private Helpers

    private func writeSourcesFile(projectId: String, sources: SourcesFile) throws {
        let projectRoot = resolveProjectRoot(projectId)
        let sourcesPath = projectRoot.appendingPathComponent("source/sources.json")
        let data = try jsonEncoder.encode(sources)
        try data.write(to: sourcesPath, options: .atomic)
    }

    private func collectFiles(
        in directory: URL,
        prefix: String,
        filter: ((String) -> Bool)? = nil,
        group: FileGroup
    ) -> [ProjectFile] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { url in
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
                  !isDir.boolValue else { return nil }

            let name = url.lastPathComponent
            if let filter, !filter(name) { return nil }

            return ProjectFile(
                path: "\(prefix)/\(name)",
                name: name,
                group: group,
                size: nil,
                modified: nil
            )
        }
    }

    private func dirContains(_ directory: URL, matching predicate: ((URL) -> Bool)? = nil) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return false }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }

        return contents.contains { url in
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
                  !isDir.boolValue else { return false }
            return predicate?(url) ?? true
        }
    }
}

// MARK: - Errors

enum ProjectServiceError: LocalizedError {
    case invalidPath
    case invalidProjectName
    case projectAlreadyExists
    case projectNotFound
    case invalidFilename
    case fileNotFound(String)
    case urlNotFound

    var errorDescription: String? {
        switch self {
        case .invalidPath: return "Invalid file path"
        case .invalidProjectName: return "Invalid project name"
        case .projectAlreadyExists: return "Project already exists"
        case .projectNotFound: return "Project not found"
        case .invalidFilename: return "Invalid filename"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .urlNotFound: return "URL not found in sources"
        }
    }
}
