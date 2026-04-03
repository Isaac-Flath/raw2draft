import Foundation
import AppKit

/// Top-level state coordinator. Manages project list, UI state, and delegates
/// file editing to EditorViewModel.
@Observable @MainActor
final class AppViewModel: ErrorHandling {
    // MARK: - Workspace
    var workspace: WorkspaceMode = .contentStudio(Constants.defaultContentPlatformRoot)

    // MARK: - State
    var projects: [Project] = []
    var activeProjectId: String? {
        didSet {
            if let id = activeProjectId {
                UserDefaults.standard.set(id, forKey: UserDefaultsKey.activeProjectId)
            }
            Task { await onProjectChanged() }
        }
    }
    var sidebarVisible: Bool = true
    var terminalVisible: Bool = true
    var settingsOpen: Bool = false
    var newProjectSheetOpen: Bool = false
    var errorMessage: String?
    var postsRefreshCounter: Int = 0

    // Distraction-free mode
    var distractionFreeMode: Bool = false
    private var sidebarWasVisible: Bool = true
    private var terminalWasVisible: Bool = true

    // Project pinning
    var pinnedProjectIds: Set<String> = []

    // Font settings
    var editorFontName: String = UserDefaults.standard.string(forKey: UserDefaultsKey.editorFontName) ?? Constants.editorFontName
    var editorFontSize: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: UserDefaultsKey.editorFontSize)
        return stored > 0 ? stored : Constants.editorFontSize
    }()

    // Rename/delete sheet state
    var renamingProject: Project?
    var renameText: String = ""
    var deletingProject: Project?

    // MARK: - Computed
    var activeProject: Project? {
        projects.first { $0.id == activeProjectId }
    }

    // MARK: - Child ViewModels
    let editor: EditorViewModel
    let terminal: TerminalViewModel
    var fileBrowser: FileBrowserViewModel?

    // MARK: - Services
    let projectService: any ProjectServiceProtocol
    let keychainService: any KeychainServiceProtocol
    let terminalService: any TerminalServiceProtocol
    let fileWatcherService: any FileWatcherServiceProtocol
    // MARK: - Private
    private var fileWatcherTask: Task<Void, Never>?

    init(
        projectService: any ProjectServiceProtocol = ProjectService(),
        keychainService: any KeychainServiceProtocol = KeychainService(),
        terminalService: any TerminalServiceProtocol = TerminalService(),
        fileWatcherService: any FileWatcherServiceProtocol = FileWatcherService()
    ) {
        self.projectService = projectService
        self.keychainService = keychainService
        self.terminalService = terminalService
        self.fileWatcherService = fileWatcherService
        self.editor = EditorViewModel(projectService: projectService)
        self.terminal = TerminalViewModel(terminalService: terminalService, keychainService: keychainService)

        setupFileWatcher()
    }

    // MARK: - Initialization

    private static let draftOpenPath = "/tmp/raw2draft-open"

    func loadInitialState() {
        // Check if launched via `draft` CLI with a specific path
        if let draftURL = consumeDraftOpenFile() {
            openWorkspace(url: draftURL)
            return
        }

        // Default: open persisted content-platform root
        let root = Constants.defaultContentPlatformRoot
        let result = WorkspaceMode.detect(url: root)
        workspace = result.mode

        // Configure services and child VMs based on workspace mode
        terminal.workingDirectory = workspace.rootURL

        switch workspace {
        case .contentStudio:
            loadContentStudioState(initialFile: result.initialFile)
        case .directory(let url):
            loadDirectoryState(url: url, initialFile: result.initialFile)
        }
    }

    /// Read and consume the temp file written by the `draft` CLI.
    private func consumeDraftOpenFile() -> URL? {
        let path = Self.draftOpenPath
        guard FileManager.default.fileExists(atPath: path),
              let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        try? FileManager.default.removeItem(atPath: path)
        return URL(fileURLWithPath: trimmed)
    }

    private func loadContentStudioState(initialFile: URL? = nil) {
        projectService.bootstrapSkillsIfNeeded()
        loadProjects()
        loadPinnedProjects()

        // Set posts directory on editor
        editor.postsDirectory = workspace.postsDirectory

        // Restore terminal visibility
        if UserDefaults.standard.object(forKey: UserDefaultsKey.terminalVisible) != nil {
            terminalVisible = UserDefaults.standard.bool(forKey: UserDefaultsKey.terminalVisible)
        }

        // If a specific file was requested, open it; otherwise restore last project
        if let file = initialFile {
            editor.openExternalFile(url: file)
        } else if let stored = UserDefaults.standard.string(forKey: UserDefaultsKey.activeProjectId),
           projects.contains(where: { $0.id == stored }) {
            activeProjectId = stored
        } else if let first = projects.first {
            activeProjectId = first.id
        }

        // Start file watcher on posts directory
        if let postsDir = workspace.postsDirectory {
            fileWatcherService.startWatching(projectsDirectory: postsDir)
        }
    }

    private func loadDirectoryState(url: URL, initialFile: URL? = nil) {
        fileBrowser = FileBrowserViewModel(rootURL: url)

        // Restore terminal visibility
        if UserDefaults.standard.object(forKey: UserDefaultsKey.terminalVisible) != nil {
            terminalVisible = UserDefaults.standard.bool(forKey: UserDefaultsKey.terminalVisible)
        }

        // Auto-open the requested file (deferred so the view hierarchy is ready)
        if let file = initialFile {
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                editor.openExternalFile(url: file, additive: true)
            }
        }

        // Watch the directory for changes
        fileWatcherService.startWatching(directory: url)
    }

    // MARK: - Project Operations

    func loadProjects() {
        do {
            projects = try projectService.listProjectStatuses()
        } catch {
            projects = []
        }
    }

    func createProject(name: String) {
        do {
            let projectId = try projectService.createProject(name: name)
            loadProjects()
            activeProjectId = projectId
            // Also create a blog post in posts/ so it appears in the posts list
            editor.createNewPost(name: name, projectId: projectId)
            postsRefreshCounter += 1
        } catch {
            showError(error.localizedDescription)
        }
    }

    func selectProject(_ projectId: String) {
        guard activeProjectId != projectId else { return }

        // Save current file before switching
        if editor.dirty {
            editor.saveCurrentFile()
        }

        activeProjectId = projectId
    }

    // MARK: - Sidebar

    func toggleSidebar() {
        sidebarVisible.toggle()
    }

    // MARK: - Terminal

    func toggleTerminal() {
        terminalVisible.toggle()
        UserDefaults.standard.set(terminalVisible, forKey: UserDefaultsKey.terminalVisible)
    }

    func sendTerminalCommand(_ command: String) {
        terminal.sendCommand(command)
    }

    // MARK: - Distraction-Free Mode

    func toggleDistractionFree() {
        if !distractionFreeMode {
            sidebarWasVisible = sidebarVisible
            terminalWasVisible = terminalVisible
            sidebarVisible = false
            terminalVisible = false
        } else {
            sidebarVisible = sidebarWasVisible
            terminalVisible = terminalWasVisible
        }
        distractionFreeMode.toggle()
    }

    // MARK: - Project Pinning

    func togglePin(_ projectId: String) {
        if pinnedProjectIds.contains(projectId) {
            pinnedProjectIds.remove(projectId)
        } else {
            pinnedProjectIds.insert(projectId)
        }
        savePinnedProjects()
    }

    private func savePinnedProjects() {
        UserDefaults.standard.set(Array(pinnedProjectIds), forKey: UserDefaultsKey.pinnedProjectIds)
    }

    private func loadPinnedProjects() {
        if let stored = UserDefaults.standard.stringArray(forKey: UserDefaultsKey.pinnedProjectIds) {
            pinnedProjectIds = Set(stored)
        }
    }

    // MARK: - Font Settings

    func updateEditorFont(name: String, size: CGFloat) {
        editorFontName = name
        editorFontSize = size
        UserDefaults.standard.set(name, forKey: UserDefaultsKey.editorFontName)
        UserDefaults.standard.set(size, forKey: UserDefaultsKey.editorFontSize)
    }

    // MARK: - Project Management

    func deleteProject(_ projectId: String) {
        do {
            terminal.removeTerminal(for: projectId)
            try projectService.deleteProject(projectId: projectId)
            pinnedProjectIds.remove(projectId)
            savePinnedProjects()
            loadProjects()
            if activeProjectId == projectId {
                activeProjectId = projects.first?.id
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func duplicateProject(_ projectId: String) {
        do {
            let newId = try projectService.duplicateProject(projectId: projectId)
            loadProjects()
            activeProjectId = newId
        } catch {
            showError(error.localizedDescription)
        }
    }

    func renameProject(_ projectId: String, newName: String) {
        do {
            let newId = try projectService.renameProject(projectId: projectId, newName: newName)
            // Update pinning
            if pinnedProjectIds.contains(projectId) {
                pinnedProjectIds.remove(projectId)
                pinnedProjectIds.insert(newId)
                savePinnedProjects()
            }
            loadProjects()
            activeProjectId = newId
        } catch {
            showError(error.localizedDescription)
        }
    }

    func revealInFinder(_ projectId: String) {
        projectService.revealInFinder(projectId: projectId)
    }

    // MARK: - Workspace

    /// Open a new file or directory, detecting the appropriate workspace mode.
    func openWorkspace(url: URL) {
        // Save current work
        if editor.dirty { editor.saveCurrentFile() }

        // Stop existing watchers
        fileWatcherService.stopWatching()

        // Reset state
        projects = []
        activeProjectId = nil
        fileBrowser = nil
        editor.files = []
        editor.activeFile = nil
        editor.fileContent = ""
        editor.dirty = false
        editor.externalFilePath = nil
        editor.openExternalFiles = []
        editor.linkedProjectId = nil
        editor.postsDirectory = nil

        // Detect and configure new workspace
        let result = WorkspaceMode.detect(url: url)
        workspace = result.mode
        terminal.workingDirectory = workspace.rootURL

        // Persist the root for content studio
        if workspace.isContentStudio {
            UserDefaults.standard.set(workspace.rootURL, forKey: UserDefaultsKey.projectsRoot)
        }

        // Save to recent workspaces
        addRecentWorkspace(workspace.rootURL)

        switch workspace {
        case .contentStudio:
            loadContentStudioState(initialFile: result.initialFile)
        case .directory(let dirURL):
            loadDirectoryState(url: dirURL, initialFile: result.initialFile)
        }
    }

    // MARK: - Recent Workspaces

    var recentWorkspaces: [URL] {
        (UserDefaults.standard.array(forKey: UserDefaultsKey.recentWorkspaces) as? [String] ?? [])
            .compactMap { URL(fileURLWithPath: $0) }
    }

    private func addRecentWorkspace(_ url: URL) {
        var recents = recentWorkspaces.map { $0.path }
        recents.removeAll { $0 == url.path }
        recents.insert(url.path, at: 0)
        if recents.count > 10 { recents = Array(recents.prefix(10)) }
        UserDefaults.standard.set(recents, forKey: UserDefaultsKey.recentWorkspaces)
    }

    // MARK: - Settings

    func reloadAfterSettingsChange() {
        guard workspace.isContentStudio else { return }
        fileWatcherService.stopWatching()
        loadProjects()
        if let postsDir = workspace.postsDirectory {
            fileWatcherService.startWatching(projectsDirectory: postsDir)
        }
        if let first = projects.first, !projects.contains(where: { $0.id == activeProjectId }) {
            activeProjectId = first.id
        }
    }

    // MARK: - Error Display

    func showError(_ message: String) {
        showError(message, autoDismiss: 5)
    }

    // MARK: - Private

    private func onProjectChanged() async {
        editor.switchProject(to: activeProjectId)
    }

    private func setupFileWatcher() {
        fileWatcherTask = Task { [weak self] in
            guard let self else { return }
            for await event in fileWatcherService.fileChanges {
                self.handleFileChange(event)
            }
        }
    }

    private func handleFileChange(_ event: FileChangeEvent) {
        if event.projectId != nil {
            // Content studio mode: refresh projects and delegate to editor
            if event.type == .added || event.type == .removed {
                loadProjects()
                postsRefreshCounter += 1
            }
            editor.handleFileChange(event)
            // Also handle externally opened post files (activeProjectId is nil)
            editor.handleExternalFileChange(absolutePath: event.absolutePath)
        } else {
            // Directory/single-file mode: refresh file browser and reload active file
            if event.type == .added || event.type == .removed {
                fileBrowser?.loadRootNodes()
            }
            editor.handleExternalFileChange(absolutePath: event.absolutePath)
        }
    }
}
