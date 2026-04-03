import SwiftUI

/// Collapsible project sources section in the editor pane.
struct ProjectSourcesView: View {
    @Bindable var viewModel: AppViewModel
    @State private var sourcesViewModel: SourcesViewModel?
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Collapsible header — full-width click target, no focus steal
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Label("Sources", systemImage: "folder")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.controlBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            // Expandable content
            if isExpanded, let sourcesVM = sourcesViewModel {
                VStack(spacing: 12) {
                    // Drop zone
                    DropZoneView(
                        onUploadFile: { url in
                            sourcesVM.uploadSourceFile(
                                from: url,
                                projectId: viewModel.activeProjectId ?? ""
                            )
                        },
                        onFilesUploaded: { refreshFiles() }
                    )

                    // Source URLs
                    SourceURLsView(
                        sourcesViewModel: sourcesVM,
                        projectId: viewModel.activeProjectId ?? ""
                    )

                    // Source text
                    SourceTextView(
                        sourcesViewModel: sourcesVM,
                        projectId: viewModel.activeProjectId ?? ""
                    )

                    // Source files list
                    SourceFilesView(
                        files: viewModel.editor.files,
                        projectRoot: viewModel.activeProjectId.map { viewModel.projectService.resolveProjectRoot($0) }
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.editorBackground)
            }
        }
        .task {
            if sourcesViewModel == nil {
                sourcesViewModel = SourcesViewModel(projectService: viewModel.projectService)
            }
            if let projectId = viewModel.activeProjectId {
                sourcesViewModel?.loadSourceUrls(projectId: projectId)
            }
        }
        .onChange(of: viewModel.activeProjectId) {
            if let projectId = viewModel.activeProjectId {
                sourcesViewModel?.loadSourceUrls(projectId: projectId)
            }
        }
        .onChange(of: sourcesViewModel?.errorMessage) {
            if let message = sourcesViewModel?.errorMessage {
                viewModel.showError(message)
                sourcesViewModel?.errorMessage = nil
            }
        }
    }

    private func refreshFiles() {
        viewModel.editor.refreshFiles()
    }
}
