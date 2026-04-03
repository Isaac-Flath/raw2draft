import SwiftUI

/// Root 3-pane layout: Sidebar | Editor | Terminal.
/// Custom HStack with DragGesture-based dividers.
struct MainContentView: View {
    @Bindable var viewModel: AppViewModel
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = Constants.sidebarDefaultWidth
    @AppStorage("terminalWidth") private var terminalWidth: Double = Constants.terminalDefaultWidth

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            if viewModel.sidebarVisible && !viewModel.distractionFreeMode {
                sidebarForMode
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading))

                // Divider between sidebar and editor
                DividerHandle()
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = sidebarWidth + value.translation.width
                                sidebarWidth = min(max(newWidth, Constants.sidebarMinWidth), Constants.sidebarMaxWidth)
                            }
                    )
            }

            // Editor (main content)
            EditorPaneView(viewModel: viewModel)
                .frame(maxWidth: .infinity)

            // Terminal (toggleable)
            if viewModel.terminalVisible && !viewModel.distractionFreeMode {
                DividerHandle()
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = terminalWidth - value.translation.width
                                terminalWidth = min(max(newWidth, Constants.terminalMinWidth), Constants.terminalMaxWidth)
                            }
                    )

                TerminalPaneView(viewModel: viewModel)
                    .frame(width: terminalWidth)
                    .transition(.move(edge: .trailing))
            } else if !viewModel.distractionFreeMode {
                // Collapsed terminal strip — click to re-expand
                Button {
                    withAnimation(.spring(response: Constants.springResponse, dampingFraction: Constants.springDamping)) {
                        viewModel.toggleTerminal()
                    }
                } label: {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "terminal")
                            .font(.system(size: 11))
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9))
                        Spacer()
                    }
                    .frame(width: 24)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(hex: Constants.TerminalColors.foreground).opacity(0.5))
                .background(Color(hex: Constants.TerminalColors.background).opacity(0.6))
                .help("Show Terminal")
            }
        }
        .animation(.spring(response: Constants.springResponse, dampingFraction: Constants.springDamping), value: viewModel.sidebarVisible)
        .animation(.spring(response: Constants.springResponse, dampingFraction: Constants.springDamping), value: viewModel.distractionFreeMode)
        .animation(.spring(response: Constants.springResponse, dampingFraction: Constants.springDamping), value: viewModel.terminalVisible)
        .overlay(alignment: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.white)
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        viewModel.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppColors.errorBackground.opacity(0.9))
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: viewModel.errorMessage)
            }
        }
        .sheet(isPresented: $viewModel.newProjectSheetOpen) {
            NewProjectSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.settingsOpen) {
            SettingsSheet(viewModel: viewModel)
        }
        .onAppear {
            viewModel.loadInitialState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileOrDirectory)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                viewModel.openWorkspace(url: url)
            }
        }
    }

    @ViewBuilder
    private var sidebarForMode: some View {
        switch viewModel.workspace {
        case .contentStudio:
            ProjectSidebarView(viewModel: viewModel)
        case .directory:
            if let fileBrowser = viewModel.fileBrowser {
                FileBrowserSidebarView(viewModel: viewModel, fileBrowser: fileBrowser)
            }
        }
    }
}

/// Draggable divider handle between panes.
struct DividerHandle: View {
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isHovered ? Color.secondary.opacity(0.3) : Color(nsColor: .separatorColor))

            // Grip indicator on hover
            if isHovered {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 3, height: 3)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: Constants.dividerWidth)
        .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: 2, x: -1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
