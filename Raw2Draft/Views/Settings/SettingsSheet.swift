import SwiftUI

/// Settings modal with .env-style key editor, font options, and cloud account.
struct SettingsSheet: View {
    @Bindable var viewModel: AppViewModel
    @State private var settingsViewModel: SettingsViewModel?
    @Environment(\.dismiss) private var dismiss

    private let fontOptions: [(name: String, label: String)] = [
        ("Lora", "Lora"),
        ("Inter", "Inter"),
        ("Georgia", "Georgia"),
        ("Palatino", "Palatino"),
        (".AppleSystemUISerif", "New York (System Serif)"),
        (".AppleSystemUIFont", "SF Pro (System Sans)"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Settings")
                    .font(AppFonts.title())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Project Root (Content Studio only)
            if viewModel.workspace.isContentStudio {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project Root")
                        .font(AppFonts.headline())

                    HStack {
                        Text(viewModel.workspace.rootURL.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button("Choose...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.message = "Select the content platform monorepo root"
                            if panel.runModal() == .OK, let url = panel.url {
                                UserDefaults.standard.set(url, forKey: UserDefaultsKey.projectsRoot)
                                viewModel.reloadAfterSettingsChange()
                            }
                        }
                        .controlSize(.small)
                    }
                }

                Divider()
            }

            // Editor Font
            VStack(alignment: .leading, spacing: 12) {
                Text("Editor Font")
                    .font(AppFonts.headline())

                HStack(spacing: 16) {
                    Picker("Font", selection: Binding(
                        get: { viewModel.editorFontName },
                        set: { viewModel.updateEditorFont(name: $0, size: viewModel.editorFontSize) }
                    )) {
                        ForEach(fontOptions, id: \.name) { option in
                            Text(option.label).tag(option.name)
                        }
                    }
                    .frame(width: 180)

                    HStack(spacing: 4) {
                        Text("Size:")
                            .font(.system(size: 12))
                        Stepper(
                            value: Binding(
                                get: { viewModel.editorFontSize },
                                set: { viewModel.updateEditorFont(name: viewModel.editorFontName, size: $0) }
                            ),
                            in: 12...24,
                            step: 1
                        ) {
                            Text("\(Int(viewModel.editorFontSize))")
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 24)
                        }
                    }
                }
            }

            if viewModel.workspace.isContentStudio, let settingsVM = settingsViewModel {
                Divider()

                // .env Editor
                EnvEditorSection(settingsViewModel: settingsVM)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 720)
        .onAppear {
            let vm = SettingsViewModel(
                envFileService: viewModel.envFileService
            )
            settingsViewModel = vm
            vm.loadStatuses()
        }
        .onChange(of: settingsViewModel?.errorMessage) {
            if let message = settingsViewModel?.errorMessage {
                viewModel.showError(message)
                settingsViewModel?.errorMessage = nil
            }
        }
    }
}

/// .env-style text editor for API keys with a reference table below.
private struct EnvEditorSection: View {
    @Bindable var settingsViewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Environment")
                    .font(AppFonts.headline())

                Text(settingsViewModel.envFilePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let confirmation = settingsViewModel.saveConfirmation {
                    Text(confirmation)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.success)
                        .transition(.opacity)
                }

                Button("Save") {
                    settingsViewModel.saveEnvText()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
            }

            // .env text editor
            TextEditor(text: Binding(
                get: { settingsViewModel.envText },
                set: {
                    settingsViewModel.envText = $0
                    settingsViewModel.saveConfirmation = nil
                }
            ))
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .frame(minHeight: 200, maxHeight: 280)

            // Key reference
            DisclosureGroup("Available Keys") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(KeychainKey.apiKeys, id: \.self) { key in
                        HStack(spacing: 0) {
                            Text(key.rawValue)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 180, alignment: .leading)
                            Text(key.hint)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }
}
