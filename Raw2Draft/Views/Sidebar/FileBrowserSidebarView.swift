import SwiftUI

/// File tree sidebar for Directory mode. Shows an expandable tree of files
/// with context menus for creating, renaming, and deleting files and directories.
struct FileBrowserSidebarView: View {
    @Bindable var viewModel: AppViewModel
    @Bindable var fileBrowser: FileBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Raw2Draft")
                        .font(AppFonts.headline())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.settingsOpen = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Settings (Cmd+,)")
                }

                HStack {
                    Text(fileBrowser.rootURL.lastPathComponent)
                        .font(AppFonts.title())
                        .lineLimit(1)
                    Spacer()

                    // New item menu (file or folder)
                    Menu {
                        Button {
                            if let url = fileBrowser.createNewFile() {
                                viewModel.editor.openExternalFile(url: url, additive: true)
                            }
                        } label: {
                            Label("New File", systemImage: "doc.badge.plus")
                        }

                        Button {
                            fileBrowser.createNewDirectory()
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 20)
                    .help("New File or Folder")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(AppColors.brandDivider)
                .frame(height: 2)
                .padding(.horizontal, 16)

            // Search and filters
            HStack(spacing: 6) {
                TextField("Search...", text: $fileBrowser.searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))

                Toggle("Recent", isOn: $fileBrowser.hideOldFiles)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .help("Show only files modified in the last 2 weeks")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // File tree
            if fileBrowser.filteredNodes.isEmpty {
                VStack {
                    Spacer()
                    Text(fileBrowser.searchText.isEmpty ? "No files found" : "No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(fileBrowser.filteredNodes) { node in
                            FileNodeRow(
                                node: node,
                                depth: 0,
                                fileBrowser: fileBrowser,
                                onOpenFile: { url in
                                    viewModel.editor.openExternalFile(url: url, additive: true)
                                },
                                onDeletedURLs: { urls in
                                    closeDeletedFiles(urls)
                                },
                                onRenamed: { oldURL, newURL in
                                    handleRename(oldURL: oldURL, newURL: newURL)
                                }
                            )
                        }
                    }
                }
                .contextMenu {
                    Button {
                        if let url = fileBrowser.createNewFile() {
                            viewModel.editor.openExternalFile(url: url, additive: true)
                        }
                    } label: {
                        Label("New File", systemImage: "doc.badge.plus")
                    }

                    Button {
                        fileBrowser.createNewDirectory()
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                }
            }

            // Footer
            HStack {
                Text(fileBrowser.rootURL.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button {
                    fileBrowser.loadRootNodes()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .background(AppColors.sidebarBackground)
        .alert(
            "Move to Trash?",
            isPresented: $fileBrowser.showDeleteConfirmation
        ) {
            Button("Move to Trash", role: .destructive) {
                let deletedURLs = fileBrowser.executeDelete()
                closeDeletedFiles(deletedURLs)
            }
            Button("Cancel", role: .cancel) {
                fileBrowser.showDeleteConfirmation = false
            }
        } message: {
            if let url = fileBrowser.pendingDeleteURL {
                if fileBrowser.pendingDeleteIsDirectory && fileBrowser.pendingDeleteItemCount > 0 {
                    Text("\"\(url.lastPathComponent)\" contains \(fileBrowser.pendingDeleteItemCount) item(s). This will move the folder and all its contents to the Trash.")
                } else {
                    Text("\"\(url.lastPathComponent)\" will be moved to the Trash.")
                }
            }
        }
    }

    private func closeDeletedFiles(_ urls: [URL]) {
        for url in urls {
            viewModel.editor.openExternalFiles.removeAll { $0 == url }
        }
        // If the active file was deleted, switch to another open file or clear
        if let activeFile = viewModel.editor.activeFile,
           urls.contains(where: { $0.path == activeFile }) {
            if let next = viewModel.editor.openExternalFiles.first {
                viewModel.editor.openExternalFile(url: next, additive: true)
            } else {
                viewModel.editor.activeFile = nil
                viewModel.editor.fileContent = ""
                viewModel.editor.files = []
            }
        }
    }

    private func handleRename(oldURL: URL, newURL: URL) {
        // Update open tabs if the renamed file was open
        if let index = viewModel.editor.openExternalFiles.firstIndex(of: oldURL) {
            viewModel.editor.openExternalFiles[index] = newURL
        }
        if viewModel.editor.activeFile == oldURL.path {
            viewModel.editor.activeFile = newURL.path
            viewModel.editor.externalFilePath = newURL
        }
        // Rebuild file list to reflect new name
        viewModel.editor.files = viewModel.editor.openExternalFiles.map { fileURL in
            ProjectFile(
                path: fileURL.path,
                name: fileURL.lastPathComponent,
                group: .content,
                size: nil,
                modified: nil
            )
        }
    }
}

/// A single row in the file tree, recursively rendering children for directories.
/// Supports context menus, inline rename, and selection highlighting.
private struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    @Bindable var fileBrowser: FileBrowserViewModel
    let onOpenFile: (URL) -> Void
    let onDeletedURLs: ([URL]) -> Void
    let onRenamed: (URL, URL) -> Void

    @State private var isHovered = false
    @FocusState private var renameFieldFocused: Bool

    private var isEditing: Bool {
        fileBrowser.editingNodeId == node.id
    }

    private var isSelected: Bool {
        fileBrowser.selectedNodeId == node.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Row content
            if isEditing {
                inlineRenameRow
            } else {
                normalRow
            }

            // Expanded children
            if node.isDirectory && node.isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileNodeRow(
                        node: child,
                        depth: depth + 1,
                        fileBrowser: fileBrowser,
                        onOpenFile: onOpenFile,
                        onDeletedURLs: onDeletedURLs,
                        onRenamed: onRenamed
                    )
                }
            }
        }
    }

    private var normalRow: some View {
        Button {
            if node.isDirectory {
                fileBrowser.toggleExpanded(node)
            } else if node.isMarkdown {
                onOpenFile(node.id)
            }
            fileBrowser.selectedNodeId = node.id
        } label: {
            rowContent(displayName: node.name)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .opacity(node.isMarkdown || node.isDirectory ? 1.0 : 0.6)
        .contextMenu { contextMenuItems }
    }

    private var inlineRenameRow: some View {
        HStack(spacing: 4) {
            Spacer().frame(width: CGFloat(depth) * 16)

            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                    .frame(width: 12)
            } else {
                Spacer().frame(width: 12)
            }

            Image(systemName: node.systemImageName)
                .font(.system(size: 11))
                .frame(width: 16)

            TextField("", text: $fileBrowser.editingName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($renameFieldFocused)
                .onSubmit { commitRename() }
                .onExitCommand { fileBrowser.cancelRename() }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(AppColors.warmTint)
        .onAppear { renameFieldFocused = true }
    }

    private func rowContent(displayName: String) -> some View {
        HStack(spacing: 4) {
            Spacer().frame(width: CGFloat(depth) * 16)

            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                    .frame(width: 12)
            } else {
                Spacer().frame(width: 12)
            }

            Image(systemName: node.systemImageName)
                .font(.system(size: 11))
                .foregroundStyle(node.isMarkdown ? .primary : .secondary)
                .frame(width: 16)

            Text(displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(node.isMarkdown || node.isDirectory ? .primary : .secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isSelected ? AppColors.warmTint.opacity(0.7) : (isHovered ? AppColors.warmTint : Color.clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if node.isDirectory {
            Button {
                fileBrowser.ensureExpanded(node)
                if let url = fileBrowser.createNewFile(in: node.id) {
                    onOpenFile(url)
                }
            } label: {
                Label("New File", systemImage: "doc.badge.plus")
            }

            Button {
                fileBrowser.ensureExpanded(node)
                fileBrowser.createNewDirectory(in: node.id)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }

            Divider()
        }

        Button {
            fileBrowser.startRename(node)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button(role: .destructive) {
            fileBrowser.confirmDelete(url: node.id, isDirectory: node.isDirectory)
        } label: {
            Label("Delete", systemImage: "trash")
        }

        Divider()

        Button {
            NSWorkspace.shared.selectFile(node.id.path, inFileViewerRootedAtPath: node.id.deletingLastPathComponent().path)
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
    }

    private func commitRename() {
        let oldURL = node.id
        if let newURL = fileBrowser.renameItem(at: oldURL, to: fileBrowser.editingName) {
            onRenamed(oldURL, newURL)
        }
    }
}
