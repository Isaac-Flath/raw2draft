import Foundation
import os

private let logger = Logger(subsystem: "com.raw2draft", category: "Editor")

/// View model for the editor pane, managing file state, content editing, and tab grouping.
@Observable @MainActor
final class EditorViewModel: ErrorHandling {
    // MARK: - File State
    var files: [ProjectFile] = []
    var activeFile: String?
    var fileContent: String = ""
    var dirty: Bool = false
    var saving: Bool = false
    var errorMessage: String?
    var lastSavedAt: Date?
    var showSaveConfirmation: Bool = false

    // Word count from editor
    var reportedWordCount: Int = 0
    var reportedCharacterCount: Int = 0

    // MARK: - Computed
    var activeProjectFile: ProjectFile? {
        guard let activeFile else { return nil }
        return files.first { $0.path == activeFile }
    }

    // MARK: - Private
    private(set) var activeProjectId: String?
    private var autosaveTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    private let projectService: any ProjectServiceProtocol

    init(projectService: any ProjectServiceProtocol) {
        self.projectService = projectService
    }

    // MARK: - Project Switching

    /// Called by AppViewModel when the active project changes.
    func switchProject(to projectId: String?) {
        activeProjectId = projectId

        guard let projectId else {
            files = []
            activeFile = nil
            fileContent = ""
            return
        }

        // Load project files
        do {
            files = try projectService.listProjectFiles(projectId: projectId)
        } catch {
            files = []
        }

        // Restore last active file or auto-select first markdown
        let lastFile = UserDefaults.standard.string(forKey: UserDefaultsKey.lastFile(for: projectId))
        if let lastFile, files.contains(where: { $0.path == lastFile }) {
            activeFile = lastFile
            loadFileContent()
        } else if let firstMarkdown = files.first(where: { $0.isMarkdown }) {
            activeFile = firstMarkdown.path
            loadFileContent()
        } else if let firstFile = files.first {
            activeFile = firstFile.path
            loadFileContent()
        } else {
            activeFile = nil
            fileContent = ""
        }
        broadcastActiveFile()
    }

    // MARK: - File Operations

    func selectFile(_ path: String) {
        guard activeFile != path else { return }

        // Save current file before switching
        if dirty {
            saveCurrentFile()
        }

        activeFile = path
        if let projectId = activeProjectId {
            UserDefaults.standard.set(path, forKey: UserDefaultsKey.lastFile(for: projectId))
        }
        loadFileContent()
        broadcastActiveFile()
    }

    func loadFileContent() {
        guard let path = activeFile else {
            fileContent = ""
            return
        }

        // External file: read directly from disk
        if openExternalFiles.contains(where: { $0.path == path }) {
            let fileURL = URL(fileURLWithPath: path)
            do {
                fileContent = try String(contentsOf: fileURL, encoding: .utf8)
                dirty = false
                errorMessage = nil
            } catch {
                fileContent = ""
                showError(error.localizedDescription)
            }
            return
        }

        // Linked project file (external post with project: frontmatter)
        if activeProjectId == nil, let linkedId = linkedProjectId {
            do {
                fileContent = try projectService.readProjectFile(projectId: linkedId, relativePath: path)
                dirty = false
                errorMessage = nil
            } catch {
                fileContent = ""
                showError(error.localizedDescription)
            }
            return
        }

        // Normal project file
        guard let projectId = activeProjectId else {
            fileContent = ""
            return
        }

        do {
            fileContent = try projectService.readProjectFile(projectId: projectId, relativePath: path)
            dirty = false
            errorMessage = nil
        } catch {
            fileContent = ""
            errorMessage = error.localizedDescription
        }
    }

    func updateContent(_ newContent: String) {
        guard fileContent != newContent else { return }
        fileContent = newContent
        dirty = true
        scheduleAutosave()
    }

    func saveCurrentFile() {
        guard dirty else { return }
        saving = true
        errorMessage = nil
        saveFile()
        saving = false
    }

    private func saveProjectFile() {
        guard let projectId = activeProjectId,
              let path = activeFile else { return }

        do {
            try projectService.writeProjectFile(projectId: projectId, relativePath: path, content: fileContent)
            markSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markSaved() {
        dirty = false
        lastSavedAt = Date()
        showSaveConfirmation = true
        confirmationTask?.cancel()
        confirmationTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.showSaveConfirmation = false
        }
    }

    func refreshFiles() {
        guard let projectId = activeProjectId else { return }
        files = (try? projectService.listProjectFiles(projectId: projectId)) ?? []
    }

    /// Called by AppViewModel when the file watcher detects a change (content studio mode).
    func handleFileChange(_ event: FileChangeEvent) {
        guard let projectId = event.projectId, projectId == activeProjectId else { return }

        refreshFiles()

        // Auto-reload active file if no unsaved edits
        guard event.path == activeFile, !dirty else { return }

        do {
            let newContent = try projectService.readProjectFile(projectId: projectId, relativePath: event.path)
            if newContent != fileContent {
                fileContent = newContent
            }
        } catch {
            logger.warning("Failed to reload file '\(event.path)': \(error.localizedDescription)")
        }
    }

    /// Called by AppViewModel when a file changes on disk (directory/single-file mode).
    /// Reloads the active file if it was changed externally.
    func handleExternalFileChange(absolutePath: String) {
        guard !dirty else { return }
        guard let activeFile, activeFile == absolutePath else { return }

        let fileURL = URL(fileURLWithPath: absolutePath)
        guard let newContent = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        if newContent != fileContent {
            fileContent = newContent
        }
    }

    // MARK: - External File

    /// Open a file outside of a project (e.g., from the posts browser or file tree).
    /// In additive mode, the file is added to the open tabs without replacing existing ones.
    func openExternalFile(url: URL, additive: Bool = false) {
        if dirty { saveCurrentFile() }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        activeProjectId = nil
        activeFile = url.path
        fileContent = content
        dirty = false
        errorMessage = nil
        externalFilePath = url
        broadcastActiveFile()

        if additive {
            // Add to open files if not already open
            if !openExternalFiles.contains(url) {
                openExternalFiles.append(url)
            }
            // Rebuild file list from all open external files
            files = openExternalFiles.map { $0.toProjectFile() }
            linkedProjectId = nil
        } else {
            // Replace mode: build file list from just this post + linked project files
            openExternalFiles = [url]
            var newFiles: [ProjectFile] = []
            newFiles.append(url.toProjectFile())

            // Check frontmatter for project: field and load its files
            let projectId = extractFrontmatterValue(content, key: "project")
            if let projectId, !projectId.isEmpty {
                linkedProjectId = projectId
                if let projectFiles = try? projectService.listProjectFiles(projectId: projectId) {
                    newFiles.append(contentsOf: projectFiles)
                }
            } else {
                linkedProjectId = nil
            }

            files = newFiles
        }
    }

    /// Project ID linked via the post's frontmatter project: field.
    var linkedProjectId: String?

    private func extractFrontmatterValue(_ content: String, key: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("\(key):") {
                var value = String(line.split(separator: ":", maxSplits: 1).last ?? "")
                    .trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Path to an externally opened file (outside of project directories).
    var externalFilePath: URL?

    /// All open external file URLs (for directory mode flat tabs).
    var openExternalFiles: [URL] = []

    /// Save handles project files, external files, and linked project files.
    private func saveFile() {
        // External file: write directly to disk
        if let activeFile, openExternalFiles.contains(where: { $0.path == activeFile }) {
            let fileURL = URL(fileURLWithPath: activeFile)
            do {
                try fileContent.write(to: fileURL, atomically: true, encoding: .utf8)
                markSaved()
            } catch {
                showError(error.localizedDescription)
            }
            return
        }

        // Linked project file (external post with project: frontmatter)
        if activeProjectId == nil, let linkedId = linkedProjectId, let path = activeFile {
            do {
                try projectService.writeProjectFile(projectId: linkedId, relativePath: path, content: fileContent)
                markSaved()
            } catch {
                showError(error.localizedDescription)
            }
            return
        }

        saveProjectFile()
    }

    // MARK: - New Post

    /// Posts directory for creating new posts (set by AppViewModel based on workspace).
    var postsDirectory: URL?

    /// Create a new post in posts/ with pre-filled frontmatter template.
    /// - Parameters:
    ///   - name: Optional post name (used for filename slug and title). Defaults to "untitled".
    ///   - projectId: Optional linked project directory name.
    /// - Returns: The URL of the created (or existing) post file, or nil on failure.
    @discardableResult
    func createNewPost(name: String? = nil, projectId: String? = nil) -> URL? {
        guard let postsDir = postsDirectory else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let slug = name.flatMap { PathSanitizer.slugify($0) } ?? "untitled"
        let dirName = "\(dateString)-\(slug)"
        let dirURL = postsDir.appendingPathComponent(dirName)
        let fileURL = dirURL.appendingPathComponent("blog.md")

        // Don't overwrite if it already exists
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            openExternalFile(url: fileURL)
            return fileURL
        }

        // Create the post directory
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            showError("Failed to create post directory: \(error.localizedDescription)")
            return nil
        }

        let title = name ?? ""
        let projectLine = projectId.map { "project: \"\($0)\"" } ?? ""
        var frontmatterLines = [
            "---",
            "title: \"\(title)\"",
            "description: \"\"",
            "author: \"Isaac Flath\"",
            "date: \"\(dateString)\"",
            "categories: []",
            "section: \"\"",
            "subsection: \"\"",
            "contentType: \"\"",
            "image: \"\"",
            "draft: true",
        ]
        if !projectLine.isEmpty {
            frontmatterLines.append(projectLine)
        }
        frontmatterLines.append("---")
        frontmatterLines.append("")

        let template = frontmatterLines.joined(separator: "\n")

        do {
            try template.write(to: fileURL, atomically: true, encoding: .utf8)
            openExternalFile(url: fileURL)
            return fileURL
        } catch {
            showError("Failed to create post: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Tab Grouping

    struct TabGroup: Identifiable {
        let id: String
        let label: String
        let files: [ProjectFile]
    }

    func groupedTabs(from files: [ProjectFile]) -> [TabGroup] {
        var groups: [FileGroup: [ProjectFile]] = [:]
        for file in files {
            groups[file.group, default: []].append(file)
        }

        return FileGroup.displayOrder.compactMap { group in
            guard let files = groups[group], !files.isEmpty else { return nil }
            return TabGroup(
                id: group.rawValue,
                label: group.label,
                files: files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            )
        }
    }

    // MARK: - Private

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(Constants.autosaveDebounceMs))
            guard !Task.isCancelled else { return }
            self.saveCurrentFile()
        }
    }

    /// Write the current active file path to ~/.raw2draft/active-file
    /// so external tools (e.g. Claude Code hooks) can read it.
    func broadcastActiveFile() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".raw2draft")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("active-file")
        let content = activeFile ?? ""
        try? content.write(to: file, atomically: true, encoding: .utf8)
    }
}
