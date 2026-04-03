import SwiftUI
import UniformTypeIdentifiers

@main
struct Raw2DraftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = AppViewModel()
    @AppStorage("showPreview") private var showPreview = false
    @AppStorage("showOutline") private var showOutline = false
    @AppStorage("showLineNumbers") private var showLineNumbers = false
    @State private var showShortcuts = false

    var body: some Scene {
        WindowGroup {
            MainContentView(viewModel: viewModel)
                .frame(minWidth: 600, minHeight: 400)
                .onOpenURL { url in
                    viewModel.openWorkspace(url: url)
                }
                .sheet(isPresented: $showShortcuts) {
                    KeyboardShortcutsSheet(isPresented: $showShortcuts)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 900)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                if viewModel.workspace.isContentStudio {
                    Button("New Project") {
                        viewModel.newProjectSheetOpen = true
                    }
                    .keyboardShortcut("n", modifiers: .command)
                } else {
                    Button("New File") {
                        if let url = viewModel.fileBrowser?.createNewFile() {
                            viewModel.editor.openExternalFile(url: url, additive: true)
                        }
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }

            CommandGroup(after: .newItem) {
                Button("Open...") {
                    openFileOrDirectory()
                }
                .keyboardShortcut("o", modifiers: .command)

                // Recent workspaces
                if !viewModel.recentWorkspaces.isEmpty {
                    Menu("Open Recent") {
                        ForEach(viewModel.recentWorkspaces, id: \.path) { url in
                            Button(url.lastPathComponent) {
                                viewModel.openWorkspace(url: url)
                            }
                        }
                    }
                }

                Divider()

                Button("Save") {
                    viewModel.editor.saveCurrentFile()
                }
                .keyboardShortcut("s", modifiers: .command)

                Divider()

                Button("Settings...") {
                    viewModel.settingsOpen = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // View menu
            CommandGroup(after: .sidebar) {
                Button(viewModel.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    withAnimation(.spring(response: Constants.springResponse, dampingFraction: Constants.springDamping)) {
                        viewModel.toggleSidebar()
                    }
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button(viewModel.terminalVisible ? "Hide Terminal" : "Show Terminal") {
                    withAnimation(.spring(response: Constants.springResponse, dampingFraction: Constants.springDamping)) {
                        viewModel.toggleTerminal()
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button(viewModel.distractionFreeMode ? "Exit Distraction-Free" : "Distraction-Free Mode") {
                    withAnimation(.spring(response: Constants.springResponse, dampingFraction: Constants.springDamping)) {
                        viewModel.toggleDistractionFree()
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button(showPreview ? "Hide Preview" : "Show Preview") {
                    showPreview.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button(showLineNumbers ? "Hide Line Numbers" : "Show Line Numbers") {
                    showLineNumbers.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Document Outline") {
                    showOutline.toggle()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") {
                    showShortcuts = true
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
    }


    private func openFileOrDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .folder]
        panel.message = "Open a file or directory"

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.openWorkspace(url: url)
        }
    }
}
