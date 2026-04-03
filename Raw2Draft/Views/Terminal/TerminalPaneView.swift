import SwiftUI
import AppKit

/// Right-side terminal pane with toolbar and action bar.
struct TerminalPaneView: View {
    @Bindable var viewModel: AppViewModel

    private var termVM: TerminalViewModel { viewModel.terminal }

    /// Terminal key: project ID in content studio, or a stable key for directory mode.
    private var terminalKey: String? {
        switch viewModel.workspace {
        case .contentStudio:
            return viewModel.activeProjectId
        case .directory(let url):
            return url.path
        }
    }

    /// Display name for the terminal toolbar.
    private var terminalLabel: String {
        switch viewModel.workspace {
        case .contentStudio:
            return viewModel.activeProject?.displayName ?? ""
        case .directory(let url):
            return url.lastPathComponent
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            TerminalToolbarView(
                projectName: terminalLabel,
                connectionStatus: termVM.connectionStatus,
                onToggle: { viewModel.toggleTerminal() },
                onRestart: {
                    guard let key = terminalKey else { return }
                    termVM.restartProcess(projectId: key)
                },
                onCopy: { termVM.copySelection() },
                onClear: { termVM.clearScreen() }
            )

            Divider()

            // Action bar (Content Studio only)
            if viewModel.workspace.isContentStudio {
                ActionBarView(
                    onCommand: { command in
                        termVM.sendCommand(command)
                    }
                )

                Divider()
            }

            // Terminal view
            if let key = terminalKey {
                GhosttyTerminalView(
                    projectId: key,
                    terminalViewModel: termVM
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text("Select a project to open terminal")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SwiftUI.Color(hex: Constants.TerminalColors.background))
            }
        }
        .background(SwiftUI.Color(hex: Constants.TerminalColors.background))
    }
}
