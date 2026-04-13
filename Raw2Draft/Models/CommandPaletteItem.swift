import Foundation

/// A single entry in the command palette.
struct CommandPaletteItem: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let kind: Kind
    let category: String

    enum Kind {
        case shortcut(keys: String, action: String)  // action ID to execute
        case skill(command: String)                   // slash command sent to terminal
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
        // (name, keys, action ID)
        let file: [(String, String, String)] = [
            ("New", "⌘N", "new"),
            ("Open", "⌘O", "open"),
            ("Save", "⌘S", "save"),
            ("Settings", "⌘,", "settings"),
        ]
        let view: [(String, String, String)] = [
            ("Toggle Sidebar", "⇧⌘B", "toggleSidebar"),
            ("Toggle Terminal", "⇧⌘T", "toggleTerminal"),
            ("Toggle Preview", "⇧⌘P", "togglePreview"),
            ("Toggle Line Numbers", "⇧⌘L", "toggleLineNumbers"),
            ("Document Outline", "⇧⌘O", "toggleOutline"),
            ("Distraction-Free Mode", "⇧⌘F", "toggleDistractionFree"),
        ]
        let editor: [(String, String, String)] = [
            ("Bold", "⌘B", "bold"),
            ("Italic", "⌘I", "italic"),
            ("Insert Link", "⌘K", "insertLink"),
            ("Find", "⌘F", "find"),
            ("Find Next", "⌘G", "findNext"),
            ("Find Previous", "⇧⌘G", "findPrevious"),
        ]
        let help: [(String, String, String)] = [
            ("Command Palette", "⌘P", "commandPalette"),
        ]

        func make(_ triples: [(String, String, String)], category: String) -> [CommandPaletteItem] {
            triples.map { CommandPaletteItem(name: $0.0, subtitle: $0.1, kind: .shortcut(keys: $0.1, action: $0.2), category: category) }
        }

        return make(file, category: "File") + make(view, category: "View")
            + make(editor, category: "Editor") + make(help, category: "Help")
    }

    // MARK: - Skills

    private static func skills() -> [CommandPaletteItem] {
        let fm = FileManager.default
        let baseDir = ClaudeContextDeployer.skillsPath
        var items: [CommandPaletteItem] = []

        for dir in findSkillsDirs(under: baseDir) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for entry in entries.sorted() {
                let skillFile = dir.appendingPathComponent(entry).appendingPathComponent("SKILL.md")
                guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else { continue }

                let (name, description) = parseFrontmatter(content)
                let command = "/\(name ?? entry)"
                items.append(CommandPaletteItem(
                    name: name ?? entry,
                    subtitle: description ?? command,
                    kind: .skill(command: command),
                    category: "Skills"
                ))
            }
        }
        return items
    }

    /// Find all `.claude/skills` directories under a base path.
    /// Handles both direct repos (base/.claude/skills) and nested repos (base/*/.claude/skills).
    private static func findSkillsDirs(under base: URL) -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        // Direct: base/.claude/skills
        let direct = base.appendingPathComponent(".claude/skills")
        if fm.fileExists(atPath: direct.path) {
            results.append(direct)
        }

        // Nested: base/*/.claude/skills (for multi-repo layouts like agentkb)
        if let children = try? fm.contentsOfDirectory(atPath: base.path) {
            for child in children where !child.hasPrefix(".") {
                let nested = base.appendingPathComponent(child).appendingPathComponent(".claude/skills")
                if fm.fileExists(atPath: nested.path) {
                    results.append(nested)
                }
            }
        }

        return results
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
