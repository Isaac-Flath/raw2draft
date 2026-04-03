import SwiftUI

/// Left sidebar showing unified posts list.
struct ProjectSidebarView: View {
    @Bindable var viewModel: AppViewModel

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
                    Text("Posts")
                        .font(AppFonts.title())

                    Spacer()

                    Button {
                        viewModel.newProjectSheetOpen = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("New Post (Cmd+N)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(AppColors.brandDivider)
                .frame(height: 2)
                .padding(.horizontal, 16)

            // Unified posts list
            PostsBrowserView(
                postsDirectory: viewModel.workspace.postsDirectory
                    ?? Constants.defaultContentPlatformRoot.appendingPathComponent("site/posts"),
                refreshTrigger: viewModel.postsRefreshCounter,
                onOpenPost: { url in
                    viewModel.editor.openExternalFile(url: url)
                },
                onDeletedURLs: { urls in
                    closeDeletedFiles(urls)
                },
                onRenamed: { oldURL, newURL in
                    handleRename(oldURL: oldURL, newURL: newURL)
                }
            )
        }
        .background(AppColors.sidebarBackground)
    }

    private func closeDeletedFiles(_ urls: [URL]) {
        for url in urls {
            viewModel.editor.openExternalFiles.removeAll { $0 == url }
        }
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
        if let index = viewModel.editor.openExternalFiles.firstIndex(of: oldURL) {
            viewModel.editor.openExternalFiles[index] = newURL
        }
        if viewModel.editor.activeFile == oldURL.path {
            viewModel.editor.activeFile = newURL.path
            viewModel.editor.externalFilePath = newURL
        }
        viewModel.editor.files = viewModel.editor.openExternalFiles.map { $0.toProjectFile() }
    }
}
