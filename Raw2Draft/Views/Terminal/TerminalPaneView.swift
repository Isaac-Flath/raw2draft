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
            if !termVM.isClaudeInstalled {
                claudeNotInstalledView
            } else if let key = terminalKey {
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

    // MARK: - Claude Not Installed

    private var claudeNotInstalledView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Claude CLI Not Found")
                .font(.headline)

            Text("Raw2Draft uses the Claude CLI for its integrated terminal.\nInstall it to get started:")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 8) {
                instructionRow("1", "Install Claude CLI from https://claude.ai/download")
                instructionRow("2", "Verify it works by running  claude --version  in Terminal")
                instructionRow("3", "Restart Raw2Draft")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
            )

            Text("Looked in: ~/.local/bin, /usr/local/bin, /opt/homebrew/bin")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SwiftUI.Color(hex: Constants.TerminalColors.background))
    }

    private func instructionRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number + ".")
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(text)
        }
        .font(.subheadline)
    }
}
