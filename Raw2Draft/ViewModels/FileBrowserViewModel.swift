import Foundation
import os

private let logger = Logger(subsystem: "com.raw2draft", category: "FileBrowser")

/// A node in the file tree — either a file or an expandable directory.
struct FileNode: Identifiable, Equatable {
    let id: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?
    var isExpanded: Bool = false

    /// Whether this is a markdown file that can be opened in the editor.
    var isMarkdown: Bool {
        guard !isDirectory else { return false }
        return Constants.markdownExtensions.contains(
            (name as NSString).pathExtension.lowercased()
        )
    }

    /// System image name for display.
    var systemImageName: String {
        if isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }
        if isMarkdown { return "doc.text" }
        let ext = (name as NSString).pathExtension.lowercased()
        if Constants.imageExtensions.contains(ext) { return "photo" }
        if Constants.videoExtensions.contains(ext) { return "film" }
        return "doc"
    }
}

/// View model for the directory mode file tree sidebar.
@Observable @MainActor
final class FileBrowserViewModel {
    var rootURL: URL
    var rootNodes: [FileNode] = []
    var searchText: String = ""
    var hideOldFiles: Bool = false

    // Selection and inline editing state
    var selectedNodeId: URL?
    var editingNodeId: URL?
    var editingName: String = ""

    // Delete confirmation state
    var pendingDeleteURL: URL?
    var pendingDeleteIsDirectory: Bool = false
    var pendingDeleteItemCount: Int = 0
    var showDeleteConfirmation: Bool = false

    private let fileManager = FileManager.default
    private static let hiddenPrefixes: Set<Character> = ["."]
    private static let hiddenDirs: Set<String> = [".git", "node_modules", "__pycache__", ".DS_Store"]

    init(rootURL: URL) {
        self.rootURL = rootURL
        loadRootNodes()
    }

    private static let recencyCutoff: TimeInterval = 14 * 24 * 60 * 60

    /// Filtered nodes matching search text and recency filter.
    var filteredNodes: [FileNode] {
        var nodes = rootNodes
        if hideOldFiles {
            let cutoff = Date().addingTimeInterval(-Self.recencyCutoff)
            nodes = filterByRecency(nodes, cutoff: cutoff)
        }
        guard !searchText.isEmpty else { return nodes }
        let query = searchText.lowercased()
        return filterNodes(nodes, query: query)
    }

    /// Load the top-level directory contents.
    func loadRootNodes() {
        rootNodes = loadChildren(of: rootURL)
    }

    /// Toggle expand/collapse for a directory node.
    func toggleExpanded(_ node: FileNode) {
        guard node.isDirectory else { return }
        toggleInPlace(node.id, in: &rootNodes)
    }

    /// Ensure a directory node is expanded (without toggling).
    func ensureExpanded(_ node: FileNode) {
        guard node.isDirectory, !node.isExpanded else { return }
        toggleInPlace(node.id, in: &rootNodes)
    }

    /// Create a new markdown file in the given directory (or root if nil).
    func createNewFile(in directory: URL? = nil) -> URL? {
        let targetDir = directory ?? rootURL
        var filename = "untitled.md"
        var counter = 1
        while fileManager.fileExists(atPath: targetDir.appendingPathComponent(filename).path) {
            counter += 1
            filename = "untitled-\(counter).md"
        }

        let fileURL = targetDir.appendingPathComponent(filename)
        do {
            try "".write(to: fileURL, atomically: true, encoding: .utf8)
            refreshPreservingState()
            expandTo(fileURL)
            editingNodeId = fileURL
            editingName = filename
            return fileURL
        } catch {
            logger.warning("Failed to create file '\(filename)': \(error.localizedDescription)")
            return nil
        }
    }

    /// Create a new directory inside the given directory (or root if nil).
    /// Returns the URL and starts inline rename.
    @discardableResult
    func createNewDirectory(in directory: URL? = nil) -> URL? {
        let targetDir = directory ?? rootURL
        var dirName = "untitled folder"
        var counter = 1
        while fileManager.fileExists(atPath: targetDir.appendingPathComponent(dirName).path) {
            counter += 1
            dirName = "untitled folder \(counter)"
        }

        let dirURL = targetDir.appendingPathComponent(dirName)
        do {
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
            refreshPreservingState()
            expandTo(dirURL)
            editingNodeId = dirURL
            editingName = dirName
            return dirURL
        } catch {
            logger.warning("Failed to create directory '\(dirName)': \(error.localizedDescription)")
            return nil
        }
    }

    /// Prepare delete confirmation for an item.
    func confirmDelete(url: URL, isDirectory: Bool) {
        pendingDeleteURL = url
        pendingDeleteIsDirectory = isDirectory
        if isDirectory {
            let contents = try? fileManager.contentsOfDirectory(atPath: url.path)
            pendingDeleteItemCount = contents?.count ?? 0
        } else {
            pendingDeleteItemCount = 0
        }
        showDeleteConfirmation = true
    }

    /// Move the pending item to Trash. Returns URLs of deleted items for editor cleanup.
    func executeDelete() -> [URL] {
        guard let url = pendingDeleteURL else { return [] }
        var deletedURLs: [URL] = []

        // Collect all file URLs that will be deleted (for editor tab cleanup)
        if pendingDeleteIsDirectory {
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    deletedURLs.append(fileURL)
                }
            }
        }
        deletedURLs.append(url)

        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
            refreshPreservingState()
        } catch {
            logger.warning("Failed to trash '\(url.lastPathComponent)': \(error.localizedDescription)")
        }

        pendingDeleteURL = nil
        showDeleteConfirmation = false
        return deletedURLs
    }

    /// Rename an item. Returns the new URL on success (for editor tab update).
    func renameItem(at url: URL, to newName: String) -> URL? {
        let newName = newName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != url.lastPathComponent else {
            editingNodeId = nil
            return nil
        }

        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard !fileManager.fileExists(atPath: newURL.path) else {
            editingNodeId = nil
            return nil
        }

        do {
            try fileManager.moveItem(at: url, to: newURL)
            editingNodeId = nil
            refreshPreservingState()
            return newURL
        } catch {
            logger.warning("Failed to rename '\(url.lastPathComponent)' to '\(newName)': \(error.localizedDescription)")
            editingNodeId = nil
            return nil
        }
    }

    /// Start inline rename for a node.
    func startRename(_ node: FileNode) {
        editingNodeId = node.id
        editingName = node.name
    }

    /// Cancel inline rename.
    func cancelRename() {
        editingNodeId = nil
        editingName = ""
    }

    // MARK: - Private

    private func loadChildren(of directory: URL) -> [FileNode] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var nodes: [FileNode] = []

        for url in contents {
            let name = url.lastPathComponent

            // Skip hidden and ignored directories
            if Self.hiddenDirs.contains(name) { continue }
            if let first = name.first, Self.hiddenPrefixes.contains(first) { continue }

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            nodes.append(FileNode(
                id: url,
                name: name,
                isDirectory: isDir.boolValue,
                children: nil,  // Lazy-loaded on expand for directories
                isExpanded: false
            ))
        }

        // Sort: directories first, then alphabetical
        nodes.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        return nodes
    }

    private func toggleInPlace(_ id: URL, in nodes: inout [FileNode]) {
        for i in nodes.indices {
            if nodes[i].id == id {
                nodes[i].isExpanded.toggle()
                if nodes[i].isExpanded && nodes[i].children == nil {
                    nodes[i].children = loadChildren(of: id)
                }
                return
            }
            if nodes[i].isDirectory, nodes[i].children != nil {
                toggleInPlace(id, in: &nodes[i].children!)
            }
        }
    }

    private func filterByRecency(_ nodes: [FileNode], cutoff: Date) -> [FileNode] {
        nodes.compactMap { node in
            if node.isDirectory {
                let children = node.children ?? loadChildren(of: node.id)
                let filtered = filterByRecency(children, cutoff: cutoff)
                if filtered.isEmpty { return nil }
                var updated = node
                updated.children = filtered
                if node.isExpanded { updated.isExpanded = true }
                return updated
            }
            // Only filter markdown files; keep non-markdown files visible
            guard node.isMarkdown else { return node }
            let attrs = try? fileManager.attributesOfItem(atPath: node.id.path)
            if let modified = attrs?[.modificationDate] as? Date, modified >= cutoff {
                return node
            }
            return nil
        }
    }

    private func filterNodes(_ nodes: [FileNode], query: String, depth: Int = 0) -> [FileNode] {
        guard depth < 10 else { return [] }
        return nodes.compactMap { node in
            if node.name.lowercased().contains(query) {
                return node
            }
            if node.isDirectory {
                let children = node.children ?? loadChildren(of: node.id)
                let filtered = filterNodes(children, query: query, depth: depth + 1)
                if !filtered.isEmpty {
                    var expanded = node
                    expanded.isExpanded = true
                    expanded.children = filtered
                    return expanded
                }
            }
            return nil
        }
    }

    /// Reload the tree while preserving expanded state.
    private func refreshPreservingState() {
        let expandedIds = collectExpandedIds(rootNodes)
        rootNodes = loadChildren(of: rootURL)
        restoreExpanded(expandedIds, in: &rootNodes)
    }

    /// Expand parent directories to reveal a URL.
    private func expandTo(_ url: URL) {
        let rootPath = rootURL.path
        let targetPath = url.deletingLastPathComponent().path
        guard targetPath.hasPrefix(rootPath) else { return }

        // Build list of ancestor directories to expand
        var current = url.deletingLastPathComponent()
        var ancestors: [URL] = []
        while current.path != rootPath && current.path.hasPrefix(rootPath) {
            ancestors.insert(current, at: 0)
            current = current.deletingLastPathComponent()
        }

        for ancestor in ancestors {
            expandInPlace(ancestor, in: &rootNodes)
        }
    }

    /// Expand a specific directory node without toggling.
    private func expandInPlace(_ id: URL, in nodes: inout [FileNode]) {
        for i in nodes.indices {
            if nodes[i].id == id && nodes[i].isDirectory {
                if !nodes[i].isExpanded {
                    nodes[i].isExpanded = true
                    if nodes[i].children == nil {
                        nodes[i].children = loadChildren(of: id)
                    }
                }
                return
            }
            if nodes[i].isDirectory, nodes[i].children != nil {
                expandInPlace(id, in: &nodes[i].children!)
            }
        }
    }

    private func collectExpandedIds(_ nodes: [FileNode]) -> Set<URL> {
        var ids = Set<URL>()
        for node in nodes {
            if node.isExpanded {
                ids.insert(node.id)
                if let children = node.children {
                    ids.formUnion(collectExpandedIds(children))
                }
            }
        }
        return ids
    }

    private func restoreExpanded(_ ids: Set<URL>, in nodes: inout [FileNode]) {
        for i in nodes.indices where nodes[i].isDirectory {
            if ids.contains(nodes[i].id) {
                nodes[i].isExpanded = true
                nodes[i].children = loadChildren(of: nodes[i].id)
                restoreExpanded(ids, in: &nodes[i].children!)
            }
        }
    }
}
