import Foundation

/// A single entry in the command palette.
struct CommandPaletteItem: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let kind: Kind
    let category: String

    enum Kind {
        case shortcut(keys: String)   // display-only, shows key combo
        case skill(command: String)   // executable, sends slash command to terminal
    }
}

/// Builds and searches the list of command palette items.
enum CommandPaletteProvider {

    static func allItems() -> [CommandPaletteItem] {
        shortcuts() + skills()
    }

    static func search(_ query: String, in items: [CommandPaletteItem]) -> [CommandPaletteItem] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter { item in
            item.name.lowercased().contains(q)
            || item.subtitle.lowercased().contains(q)
            || item.category.lowercased().contains(q)
            || {
                if case .skill(let cmd) = item.kind { return cmd.lowercased().contains(q) }
                return false
            }()
        }
    }

    // MARK: - Keyboard Shortcuts

    private static func shortcuts() -> [CommandPaletteItem] {
        let file: [(String, String)] = [
            ("New", "⌘N"), ("Open", "⌘O"), ("Save", "⌘S"), ("Settings", "⌘,"),
        ]
        let view: [(String, String)] = [
            ("Toggle Sidebar", "⇧⌘B"), ("Toggle Terminal", "⇧⌘T"),
            ("Toggle Preview", "⇧⌘P"), ("Toggle Line Numbers", "⇧⌘L"),
            ("Document Outline", "⇧⌘O"), ("Distraction-Free Mode", "⇧⌘F"),
            ("Command Palette", "⇧⌘K"),
        ]
        let editor: [(String, String)] = [
            ("Bold", "⌘B"), ("Italic", "⌘I"), ("Insert Link", "⌘K"),
            ("Find", "⌘F"), ("Find Next", "⌘G"), ("Find Previous", "⇧⌘G"),
        ]
        let help: [(String, String)] = [
            ("Keyboard Shortcuts", "⌘/"),
        ]

        func make(_ pairs: [(String, String)], category: String) -> [CommandPaletteItem] {
            pairs.map { CommandPaletteItem(name: $0.0, subtitle: $0.1, kind: .shortcut(keys: $0.1), category: category) }
        }

        return make(file, category: "File") + make(view, category: "View")
            + make(editor, category: "Editor") + make(help, category: "Help")
    }

    // MARK: - Skills

    private static func skills() -> [CommandPaletteItem] {
        let skillsDir = ClaudeContextDeployer.deployedPath
            .appendingPathComponent(".claude/skills")
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: skillsDir.path) else { return [] }

        return entries.sorted().compactMap { entry in
            let skillFile = skillsDir.appendingPathComponent(entry).appendingPathComponent("SKILL.md")
            guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else { return nil }

            let (name, description) = parseFrontmatter(content)
            let command = "/\(name ?? entry)"
            return CommandPaletteItem(
                name: name ?? entry,
                subtitle: description ?? command,
                kind: .skill(command: command),
                category: "Skills"
            )
        }
    }

    private static func parseFrontmatter(_ content: String) -> (name: String?, description: String?) {
        let lines = content.components(separatedBy: "\n")
        guard lines.first == "---" else { return (nil, nil) }

        var name: String?
        var description: String?

        for line in lines.dropFirst() {
            if line == "---" { break }
            if line.hasPrefix("name:") {
                name = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("description:") {
                description = line.dropFirst(12).trimmingCharacters(in: .whitespaces)
            }
        }
        return (name, description)
    }
}
