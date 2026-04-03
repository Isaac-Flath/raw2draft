import SwiftUI

/// VS Code-style command palette overlay.
struct CommandPaletteView: View {
    @Bindable var viewModel: AppViewModel
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var scrollToSelection: Bool = false
    @FocusState private var searchFocused: Bool

    private let allItems = CommandPaletteProvider.allItems()

    private var filteredItems: [CommandPaletteItem] {
        CommandPaletteProvider.search(query, in: allItems)
    }

    /// Flat list of rows: either a section header or an item with its global index.
    private var rows: [PaletteRow] {
        let items = filteredItems
        let grouped = Dictionary(grouping: items) { $0.category }
        let categoryOrder = ["File", "View", "Editor", "Help", "Skills"]

        var result: [PaletteRow] = []
        for category in categoryOrder {
            guard let categoryItems = grouped[category] else { continue }
            result.append(.header(category))
            for item in categoryItems {
                let index = items.firstIndex(where: { $0.id == item.id }) ?? 0
                result.append(.item(item, globalIndex: index))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                    .onChange(of: query) {
                        selectedIndex = 0
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            switch row {
                            case .header(let title):
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)

                            case .item(let item, let globalIndex):
                                PaletteItemRow(
                                    item: item,
                                    isSelected: globalIndex == selectedIndex
                                )
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture { execute(item) }
                                .onHover { hovering in
                                    if hovering { selectedIndex = globalIndex }
                                }
                            }
                        }

                        if filteredItems.isEmpty {
                            Text("No matches")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }
                    }
                }
                .frame(maxHeight: 340)
                .onChange(of: scrollToSelection) {
                    if scrollToSelection, let item = filteredItems[safe: selectedIndex] {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                    scrollToSelection = false
                }
            }
        }
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        .onAppear { searchFocused = true }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            scrollToSelection = true
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(filteredItems.count - 1, selectedIndex + 1)
            scrollToSelection = true
            return .handled
        }
        .onKeyPress(.return) {
            if let item = filteredItems[safe: selectedIndex] {
                execute(item)
            }
            return .handled
        }
        .onKeyPress(.escape) {
            viewModel.commandPaletteVisible = false
            return .handled
        }
    }

    private func execute(_ item: CommandPaletteItem) {
        viewModel.commandPaletteVisible = false

        switch item.kind {
        case .shortcut(_, let action):
            executeShortcut(action)
        case .skill(let command):
            if !viewModel.terminalVisible {
                viewModel.terminalVisible = true
            }
            viewModel.sendTerminalCommand(command)
        }
    }

    private func executeShortcut(_ action: String) {
        let defaults = UserDefaults.standard
        let anim = Animation.spring(response: Constants.springResponse, dampingFraction: Constants.springDamping)

        switch action {
        // File
        case "new":
            if viewModel.workspace.isContentStudio {
                viewModel.newProjectSheetOpen = true
            } else if let url = viewModel.fileBrowser?.createNewFile() {
                viewModel.editor.openExternalFile(url: url, additive: true)
            }
        case "save":
            viewModel.editor.saveCurrentFile()
        case "settings":
            viewModel.settingsOpen = true

        // View
        case "toggleSidebar":
            withAnimation(anim) { viewModel.toggleSidebar() }
        case "toggleTerminal":
            withAnimation(anim) { viewModel.toggleTerminal() }
        case "togglePreview":
            defaults.set(!defaults.bool(forKey: "showPreview"), forKey: "showPreview")
        case "toggleLineNumbers":
            defaults.set(!defaults.bool(forKey: "showLineNumbers"), forKey: "showLineNumbers")
        case "toggleOutline":
            defaults.set(!defaults.bool(forKey: "showOutline"), forKey: "showOutline")
        case "toggleDistractionFree":
            withAnimation(anim) { viewModel.toggleDistractionFree() }

        // Editor — send key equivalent to the editor webview
        case "bold":
            sendEditorKey("b", modifiers: .command)
        case "italic":
            sendEditorKey("i", modifiers: .command)
        case "insertLink":
            sendEditorKey("k", modifiers: .command)
        case "find":
            sendEditorKey("f", modifiers: .command)
        case "findNext":
            sendEditorKey("g", modifiers: .command)
        case "findPrevious":
            sendEditorKey("g", modifiers: [.command, .shift])

        default:
            break
        }
    }

    /// Synthesize a key event and send it through the menu system.
    private func sendEditorKey(_ key: String, modifiers: NSEvent.ModifierFlags) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: NSApp.mainWindow?.windowNumber ?? 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: 0
        ) else { return }
        NSApp.mainMenu?.performKeyEquivalent(with: event)
    }
}

// MARK: - Row types

private enum PaletteRow: Identifiable {
    case header(String)
    case item(CommandPaletteItem, globalIndex: Int)

    var id: String {
        switch self {
        case .header(let title): return "header-\(title)"
        case .item(let item, _): return item.id.uuidString
        }
    }
}

private struct PaletteItemRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(item.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            switch item.kind {
            case .shortcut(let keys, _):
                Text(keys)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            case .skill(let command):
                Text(command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? AppColors.warmTintActive : Color.clear)
    }

    private var icon: String {
        switch item.kind {
        case .shortcut: return "keyboard"
        case .skill: return "terminal"
        }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
