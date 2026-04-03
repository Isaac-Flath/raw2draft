import SwiftUI
import os

private let logger = Logger(subsystem: "com.raw2draft", category: "PostsBrowser")

/// Browse all posts in posts/ with filtering and status indicators.
/// Posts expand to show their directory contents for file navigation.
/// Supports creating, renaming, and deleting both posts and files within posts.
struct PostsBrowserView: View {
    @State private var posts: [BlogPost] = []
    @State private var searchText = ""
    @State private var sectionFilter = ""
    @State private var showDraftsOnly = false
    @State private var hideOldPosts = false
    @State private var expandedPostIds: Set<String> = []
    @State private var postFiles: [String: [URL]] = [:]
    @State private var newDirectoryName = ""
    @State private var showNewDirectorySheet = false

    // Inline rename state
    @State private var editingURL: URL?
    @State private var editingName: String = ""

    // Delete confirmation state
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteURL: URL?
    @State private var pendingDeleteName: String = ""
    @State private var pendingDeleteIsDirectory = false
    @State private var pendingDeleteItemCount = 0

    let postsDirectory: URL
    var refreshTrigger: Int = 0
    let onOpenPost: (URL) -> Void
    var onDeletedURLs: (([URL]) -> Void)?
    var onRenamed: ((URL, URL) -> Void)?

    private var sections: [String] {
        Array(Set(posts.map { $0.section }).filter { !$0.isEmpty }).sorted()
    }

    private static let recencyCutoff: TimeInterval = 14 * 24 * 60 * 60 // 14 days

    private var filteredPosts: [BlogPost] {
        posts.filter { post in
            if showDraftsOnly && !post.isDraft { return false }
            if !sectionFilter.isEmpty && post.section != sectionFilter { return false }
            if hideOldPosts {
                let isUpcoming = post.status == .draft || post.status == .scheduled
                if !isUpcoming {
                    let cutoff = Date().addingTimeInterval(-Self.recencyCutoff)
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    if let postDate = formatter.date(from: post.date), postDate < cutoff {
                        return false
                    }
                }
            }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return post.title.lowercased().contains(query)
                    || post.slug.lowercased().contains(query)
                    || post.section.lowercased().contains(query)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters
            HStack(spacing: 6) {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)

                if !sections.isEmpty {
                    Picker("", selection: $sectionFilter) {
                        Text("All").tag("")
                        ForEach(sections, id: \.self) { section in
                            Text(section).tag(section)
                        }
                    }
                    .frame(width: 90)
                    .font(.system(size: 11))
                }

                Toggle("Drafts", isOn: $showDraftsOnly)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                Toggle("Recent", isOn: $hideOldPosts)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .help("Show only posts from the last 2 weeks (plus drafts and scheduled)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Post list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredPosts) { post in
                        PostRowView(
                            post: post,
                            isExpanded: expandedPostIds.contains(post.id),
                            files: postFiles[post.id] ?? [],
                            editingURL: $editingURL,
                            editingName: $editingName,
                            onToggleExpand: { toggleExpand(post) },
                            onOpenFile: { onOpenPost($0) },
                            onCreateFile: { createFileInline(in: post) },
                            onCreateFolder: { createFolderInline(in: post) },
                            onConfirmDelete: { url, name, isDir in
                                confirmDelete(url: url, name: name, isDirectory: isDir)
                            },
                            onCommitRename: { oldURL, newName in
                                commitRename(oldURL: oldURL, newName: newName)
                            },
                            onDeletePost: {
                                let postDir = post.filePath.deletingLastPathComponent()
                                confirmDelete(
                                    url: postDir,
                                    name: post.title.isEmpty ? post.slug : post.title,
                                    isDirectory: true
                                )
                            },
                            onRenamePost: {
                                editingURL = post.filePath.deletingLastPathComponent()
                                editingName = post.filePath.deletingLastPathComponent().lastPathComponent
                            }
                        )
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .contextMenu {
                Button {
                    showNewDirectorySheet = true
                } label: {
                    Label("New Post", systemImage: "folder.badge.plus")
                }
            }

            // Footer with count and refresh
            HStack {
                Text("\(filteredPosts.count) posts")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    reloadPosts()
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
        .onAppear {
            reloadPosts()
        }
        .onChange(of: refreshTrigger) {
            reloadPosts()
        }
        .sheet(isPresented: $showNewDirectorySheet) {
            NewDirectorySheet(
                name: $newDirectoryName,
                onCreate: { createDirectory(name: newDirectoryName) },
                onCancel: { showNewDirectorySheet = false; newDirectoryName = "" }
            )
        }
        .alert(
            "Move to Trash?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Move to Trash", role: .destructive) {
                executeDelete()
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
            }
        } message: {
            if pendingDeleteIsDirectory && pendingDeleteItemCount > 0 {
                Text("\"\(pendingDeleteName)\" contains \(pendingDeleteItemCount) item(s). This will move it and all its contents to the Trash.")
            } else {
                Text("\"\(pendingDeleteName)\" will be moved to the Trash.")
            }
        }
    }

    private func reloadPosts() {
        posts = BlogPostParser.loadPosts(from: postsDirectory)
        // Refresh files for any expanded posts
        for postId in expandedPostIds {
            if let post = posts.first(where: { $0.id == postId }) {
                loadFiles(for: post)
            }
        }
    }

    private func toggleExpand(_ post: BlogPost) {
        if expandedPostIds.contains(post.id) {
            expandedPostIds.remove(post.id)
        } else {
            expandedPostIds.insert(post.id)
            loadFiles(for: post)
            onOpenPost(post.filePath)
        }
    }

    private func loadFiles(for post: BlogPost) {
        let postDir = post.filePath.deletingLastPathComponent()
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: postDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            postFiles[post.id] = []
            return
        }

        let sorted = contents.sorted { a, b in
            let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aIsDir != bIsDir { return aIsDir }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
        postFiles[post.id] = sorted
    }

    // MARK: - Create

    private func createDirectory(name: String) {
        guard !name.isEmpty else { return }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let dirName = "\(dateString)-\(slug)"
        let dirURL = postsDirectory.appendingPathComponent(dirName)
        let blogFile = dirURL.appendingPathComponent("blog.md")

        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let author = UserDefaults.standard.string(forKey: UserDefaultsKey.defaultAuthor) ?? ""
            let template = """
            ---
            title: "\(name)"
            author: "\(author)"
            date: "\(dateString)"
            draft: true
            ---

            """
            try template.write(to: blogFile, atomically: true, encoding: .utf8)
            showNewDirectorySheet = false
            newDirectoryName = ""
            reloadPosts()
            onOpenPost(blogFile)
        } catch {
            logger.error("Failed to create post directory '\(name)': \(error.localizedDescription)")
        }
    }

    private func createFileInline(in post: BlogPost) {
        let postDir = post.filePath.deletingLastPathComponent()
        var filename = "untitled.md"
        var counter = 1
        while FileManager.default.fileExists(atPath: postDir.appendingPathComponent(filename).path) {
            counter += 1
            filename = "untitled-\(counter).md"
        }

        let fileURL = postDir.appendingPathComponent(filename)
        do {
            try "".write(to: fileURL, atomically: true, encoding: .utf8)
            // Expand the post and refresh files
            expandedPostIds.insert(post.id)
            loadFiles(for: post)
            // Start inline rename on the new file
            editingURL = fileURL
            editingName = filename
        } catch {
            logger.error("Failed to create file '\(filename)': \(error.localizedDescription)")
        }
    }

    private func createFolderInline(in post: BlogPost) {
        let postDir = post.filePath.deletingLastPathComponent()
        var dirName = "untitled folder"
        var counter = 1
        while FileManager.default.fileExists(atPath: postDir.appendingPathComponent(dirName).path) {
            counter += 1
            dirName = "untitled folder \(counter)"
        }

        let dirURL = postDir.appendingPathComponent(dirName)
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            expandedPostIds.insert(post.id)
            loadFiles(for: post)
            editingURL = dirURL
            editingName = dirName
        } catch {
            logger.error("Failed to create folder '\(dirName)': \(error.localizedDescription)")
        }
    }

    // MARK: - Rename

    private func commitRename(oldURL: URL, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldURL.lastPathComponent else {
            editingURL = nil
            return
        }

        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            editingURL = nil
            return
        }

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            editingURL = nil
            onRenamed?(oldURL, newURL)
            reloadPosts()
        } catch {
            logger.error("Failed to rename '\(oldURL.lastPathComponent)' to '\(trimmed)': \(error.localizedDescription)")
            editingURL = nil
        }
    }

    // MARK: - Delete

    private func confirmDelete(url: URL, name: String, isDirectory: Bool) {
        pendingDeleteURL = url
        pendingDeleteName = name
        pendingDeleteIsDirectory = isDirectory
        if isDirectory {
            let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path)
            pendingDeleteItemCount = contents?.count ?? 0
        } else {
            pendingDeleteItemCount = 0
        }
        showDeleteConfirmation = true
    }

    private func executeDelete() {
        guard let url = pendingDeleteURL else { return }
        var deletedURLs: [URL] = []

        if pendingDeleteIsDirectory {
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    deletedURLs.append(fileURL)
                }
            }
        }
        deletedURLs.append(url)

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            onDeletedURLs?(deletedURLs)
            reloadPosts()
        } catch {
            logger.error("Failed to trash '\(url.lastPathComponent)': \(error.localizedDescription)")
        }

        pendingDeleteURL = nil
        showDeleteConfirmation = false
    }
}

// MARK: - Post Row

private struct PostRowView: View {
    let post: BlogPost
    let isExpanded: Bool
    let files: [URL]
    @Binding var editingURL: URL?
    @Binding var editingName: String
    let onToggleExpand: () -> Void
    let onOpenFile: (URL) -> Void
    let onCreateFile: () -> Void
    let onCreateFolder: () -> Void
    let onConfirmDelete: (URL, String, Bool) -> Void
    let onCommitRename: (URL, String) -> Void
    let onDeletePost: () -> Void
    let onRenamePost: () -> Void

    @State private var isHovered = false
    @FocusState private var renameFieldFocused: Bool

    private var postDir: URL {
        post.filePath.deletingLastPathComponent()
    }

    private var isEditingPostDir: Bool {
        editingURL == postDir
    }

    private var statusColor: Color {
        switch post.status {
        case .draft: return AppColors.gold
        case .scheduled: return AppColors.indigo
        case .published: return AppColors.stagePublished
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Post header row
            if isEditingPostDir {
                postDirRenameRow
            } else {
                postHeaderRow
            }

            // Expanded file list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(files, id: \.path) { fileURL in
                        PostFileRow(
                            fileURL: fileURL,
                            editingURL: $editingURL,
                            editingName: $editingName,
                            onOpen: { onOpenFile(fileURL) },
                            onConfirmDelete: onConfirmDelete,
                            onCommitRename: onCommitRename
                        )
                    }
                }
            }
        }
    }

    private var postHeaderRow: some View {
        Button(action: onToggleExpand) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
                    .frame(width: 12)

                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.title.isEmpty ? post.slug : post.title)
                        .font(AppFonts.serif(12, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if !post.date.isEmpty {
                            Text(post.date)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        if !post.section.isEmpty {
                            Text(post.section)
                                .font(.system(size: 10))
                        }
                        Text("\(post.wordCount)w")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? AppColors.warmTint : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(post.publicURL)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(post.publicURL, forType: .string)
            } label: {
                Label("Copy URL", systemImage: "link")
            }

            Divider()

            Button {
                onCreateFile()
            } label: {
                Label("New File", systemImage: "doc.badge.plus")
            }

            Button {
                onCreateFolder()
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }

            Divider()

            Button {
                onRenamePost()
            } label: {
                Label("Rename Directory", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDeletePost()
            } label: {
                Label("Delete Post", systemImage: "trash")
            }

            Divider()

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: postDir.path)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }

    private var postDirRenameRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12)

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            TextField("", text: $editingName)
                .textFieldStyle(.plain)
                .font(AppFonts.serif(12, weight: .medium))
                .focused($renameFieldFocused)
                .onSubmit {
                    onCommitRename(postDir, editingName)
                }
                .onExitCommand {
                    editingURL = nil
                    editingName = ""
                }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppColors.warmTint)
        .onAppear { renameFieldFocused = true }
    }
}

// MARK: - File Row (within expanded post)

private struct PostFileRow: View {
    let fileURL: URL
    @Binding var editingURL: URL?
    @Binding var editingName: String
    let onOpen: () -> Void
    let onConfirmDelete: (URL, String, Bool) -> Void
    let onCommitRename: (URL, String) -> Void

    @State private var isHovered = false
    @FocusState private var renameFieldFocused: Bool

    private var isDirectory: Bool {
        (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private var isEditing: Bool {
        editingURL == fileURL
    }

    private var iconName: String {
        if isDirectory { return "folder" }
        let ext = fileURL.pathExtension.lowercased()
        if ["md", "markdown", "qmd"].contains(ext) { return "doc.text" }
        if ["png", "jpg", "jpeg", "gif", "webp", "svg"].contains(ext) { return "photo" }
        if ["mp4", "mov", "mkv", "webm"].contains(ext) { return "film" }
        return "doc"
    }

    var body: some View {
        if isEditing {
            renameRow
        } else {
            normalRow
        }
    }

    private var normalRow: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                Text(fileURL.lastPathComponent)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.leading, 42)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(isHovered ? AppColors.warmTint : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                editingURL = fileURL
                editingName = fileURL.lastPathComponent
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onConfirmDelete(fileURL, fileURL.lastPathComponent, isDirectory)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Divider()

            Button {
                NSWorkspace.shared.selectFile(
                    fileURL.path,
                    inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path
                )
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }

    private var renameRow: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            TextField("", text: $editingName)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($renameFieldFocused)
                .onSubmit {
                    onCommitRename(fileURL, editingName)
                }
                .onExitCommand {
                    editingURL = nil
                    editingName = ""
                }

            Spacer()
        }
        .padding(.leading, 42)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(AppColors.warmTint)
        .onAppear { renameFieldFocused = true }
    }
}

// MARK: - New Directory Sheet

private struct NewDirectorySheet: View {
    @Binding var name: String
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Post Directory")
                .font(AppFonts.headline())

            TextField("Post name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if !name.isEmpty { onCreate() } }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

// MARK: - String + Identifiable for sheet binding

extension String: @retroactive Identifiable {
    public var id: String { self }
}
