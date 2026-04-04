import SwiftUI
import AppKit

/// Main editor pane with file tabs, editor surface, and toolbar.
struct EditorPaneView: View {
    @Bindable var viewModel: AppViewModel
    @AppStorage("showOutline") private var showOutline = false
    @AppStorage("showLineNumbers") private var showLineNumbers = false
    @State private var scrollToOffset: Int?
    @State private var scrollToHeadingIndex: Int?
    @State private var socialMode = false
    @AppStorage("showPreview") private var showPreview = false

    private var hasContent: Bool {
        viewModel.editor.activeFile != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasContent {
                // Editor surface
                editorSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Footer toolbar
                editorFooter
            } else {
                VStack {
                    Spacer()
                    Text(viewModel.workspace.isContentStudio ? "Select a post to begin" : "Select a file to begin")
                        .font(AppFonts.title(17))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColors.editorBackground)
    }

    // MARK: - Editor Surface

    @ViewBuilder
    private var editorSurface: some View {
        if let file = viewModel.editor.activeProjectFile {
            if file.isMarkdown {
                MarkdownEditorWebView(
                    content: viewModel.editor.fileContent,
                    fontName: viewModel.editorFontName,
                    fontSize: viewModel.editorFontSize,
                    socialMode: socialMode,
                    showPreview: showPreview,
                    showLineNumbers: showLineNumbers,
                    scrollToOffset: $scrollToOffset,
                    scrollToHeadingIndex: $scrollToHeadingIndex,
                    onContentChanged: { viewModel.editor.updateContent($0) },
                    onSave: { viewModel.editor.saveCurrentFile() },
                    onWordCount: { words, chars in
                        viewModel.editor.reportedWordCount = words
                        viewModel.editor.reportedCharacterCount = chars
                    },
                    onCursorPosition: { _, _ in },
                    onSendToTerminal: { viewModel.sendTerminalCommand($0) },
                    envLookup: { key in
                        if let apiKey = APIKey(rawValue: key),
                           let value = viewModel.envFileService.getKey(apiKey) {
                            return value
                        }
                        return ProcessInfo.processInfo.environment[key]
                    }
                )
            } else if file.isImage {
                ImagePreviewView(
                    projectId: viewModel.activeProjectId ?? "",
                    relativePath: file.path,
                    projectService: viewModel.projectService
                )
            } else if file.isVideo {
                VideoPlayerView(
                    projectId: viewModel.activeProjectId ?? "",
                    relativePath: file.path,
                    projectService: viewModel.projectService
                )
            } else {
                // Plain text fallback
                TextEditor(text: Binding(
                    get: { viewModel.editor.fileContent },
                    set: { viewModel.editor.updateContent($0) }
                ))
                .font(.system(size: 14, design: .monospaced))
            }
        } else {
            VStack {
                Spacer()
                Text("No file selected")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Footer

    private var editorFooter: some View {
        HStack(spacing: 12) {
            // Current filename
            if let file = viewModel.editor.activeProjectFile {
                Text(file.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Save indicator
            if viewModel.editor.showSaveConfirmation {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                        .font(.system(size: 11))
                    Text("Saved")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.success)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else if viewModel.editor.dirty {
                Circle()
                    .fill(AppColors.gold)
                    .frame(width: 8, height: 8)
            }

            if let error = viewModel.editor.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.statusError)
            }

            // Open in Finder
            Button {
                if let externalPath = viewModel.editor.externalFilePath {
                    NSWorkspace.shared.selectFile(externalPath.path, inFileViewerRootedAtPath: externalPath.deletingLastPathComponent().path)
                } else if let projectId = viewModel.activeProjectId {
                    viewModel.revealInFinder(projectId)
                }
            } label: {
                Label("Open in Finder", systemImage: "folder")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open in Finder")

            Spacer()

            // Social mode toggle (Content Studio only)
            if viewModel.workspace.isContentStudio,
               viewModel.editor.activeProjectFile?.isMarkdown == true {
                Button {
                    socialMode.toggle()
                } label: {
                    Label("Social", systemImage: "rectangle.portrait")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(socialMode ? Color.accentColor : nil)
                .help("Toggle social media preview width (550px)")
            }

            // Line numbers toggle
            if viewModel.editor.activeProjectFile?.isMarkdown == true {
                Button {
                    showLineNumbers.toggle()
                } label: {
                    Label("Lines", systemImage: "list.number")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(showLineNumbers ? Color.accentColor : nil)
                .help("Toggle line numbers (Shift+Cmd+L)")
            }

            // View menu: Save, Preview, Outline
            Menu {
                Button {
                    viewModel.editor.saveCurrentFile()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!viewModel.editor.dirty)

                if viewModel.editor.activeProjectFile?.isMarkdown == true {
                    Divider()

                    Button {
                        showPreview.toggle()
                    } label: {
                        if showPreview {
                            Label("Hide Preview", systemImage: "eye.slash")
                        } else {
                            Label("Show Preview", systemImage: "eye")
                        }
                    }

                    Button {
                        showOutline.toggle()
                    } label: {
                        Label("Outline", systemImage: "list.bullet.indent")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Save, Preview, Outline")
            .popover(isPresented: $showOutline) {
                HeadingOutlinePopover(
                    headings: MarkdownParserUtil.parseHeadings(from: viewModel.editor.fileContent),
                    onSelect: { offset, headingIndex in
                        scrollToOffset = offset
                        scrollToHeadingIndex = headingIndex
                        showOutline = false
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppColors.controlBackground)
        .animation(.spring(response: Constants.springResponse), value: viewModel.editor.showSaveConfirmation)
    }
}
