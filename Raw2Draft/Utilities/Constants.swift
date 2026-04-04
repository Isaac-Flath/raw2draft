import Foundation

enum Constants {
    // MARK: - Timing
    static let autosaveDebounceMs: Int = 900
    static let uploadStatusResetMs: Int = 3000
    static let terminalResizeDebounceMs: Int = 80
    static let watcherStabilityThresholdMs: Int = 100
    static let watcherPollIntervalMs: Int = 50

    // MARK: - Terminal (matched to Ghostty "Writer's Room" config)
    static let terminalInitialCols: Int = 120
    static let terminalInitialRows: Int = 36
    static let terminalScrollbackLines: Int = 5000
    static let terminalFontSize: CGFloat = 15
    static let terminalFontName: String = "JetBrainsMono-Regular"
    static let terminalFontNameFallback: String = "Menlo"
    static let terminalCellHeightMultiplier: CGFloat = 1.3 // matches Ghostty adjust-cell-height = 30%

    // MARK: - Terminal Colors (matched to Ghostty light theme)
    enum TerminalColors {
        static let background = "#f5f6f8"
        static let foreground = "#1a1a1a"
        static let cursor = "#0088ff"
        // Ghostty default palette (0-15)
        static let black = "#1d1f21"
        static let red = "#cc6666"
        static let green = "#b5bd68"
        static let yellow = "#f0c674"
        static let blue = "#81a2be"
        static let magenta = "#b294bb"
        static let cyan = "#8abeb7"
        static let white = "#c5c8c6"
        static let brightBlack = "#666666"
        static let brightRed = "#d54e53"
        static let brightGreen = "#b9ca4a"
        static let brightYellow = "#e7c547"
        static let brightBlue = "#7aa6da"
        static let brightMagenta = "#c397d8"
        static let brightCyan = "#70c0b1"
        static let brightWhite = "#eaeaea"
    }

    // MARK: - Editor
    static let editorFontName: String = "Lora"
    static let editorFontSize: CGFloat = 18
    static let editorLineHeight: CGFloat = 1.95
    static let editorMaxContentWidth: CGFloat = 740
    static let editorSocialContentWidth: CGFloat = 550
    static let editorCursorColor = "#4f46e5"

    // MARK: - Editor Heading Sizes (matches website rem values)
    enum HeadingScale {
        static let h1: CGFloat = 2.25
        static let h2: CGFloat = 2.0
        static let h3: CGFloat = 1.5
        static let h4: CGFloat = 1.125
    }

    // MARK: - Animations
    static let springResponse: Double = 0.3
    static let springDamping: Double = 0.8

    // MARK: - Layout
    static let sidebarDefaultWidth: CGFloat = 260
    static let sidebarMinWidth: CGFloat = 180
    static let sidebarMaxWidth: CGFloat = 400
    static let terminalDefaultWidth: CGFloat = 520
    static let terminalMinWidth: CGFloat = 450
    static let terminalMaxWidth: CGFloat = 800
    static let dividerWidth: CGFloat = 6

    // MARK: - Paths
    static let appName = "Raw2Draft"

    /// Default content root. Set via Settings on first launch.
    static var defaultContentPlatformRoot: URL {
        UserDefaults.standard.url(forKey: UserDefaultsKey.projectsRoot)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents")
    }

    // MARK: - Project Subdirectories (Content Studio only)
    static let projectSubdirs = ["source", "video", "social", "screenshots", "images"]

    // MARK: - Date Formatting
    static let projectDateFormat = "yyyy_MM_dd"
    private static let projectDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = projectDateFormat
        return formatter
    }()
    static func projectDateString(from date: Date = Date()) -> String {
        projectDateFormatter.string(from: date)
    }

    static let postDateFormat = "yyyy-MM-dd"
    private static let postDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = postDateFormat
        return formatter
    }()
    static func postDateString(from date: Date = Date()) -> String {
        postDateFormatter.string(from: date)
    }

    // MARK: - File Extensions
    static let videoExtensions: Set<String> = ["mp4", "mov", "webm"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]
    static let markdownExtensions: Set<String> = ["md", "mdx", "markdown"]

    // MARK: - IPC
    /// Temp file used by the `draft` CLI to pass a path to the running app.
    static let draftOpenFile: URL = FileManager.default.temporaryDirectory.appendingPathComponent("raw2draft-open")

    // MARK: - URL Scheme
    static let urlScheme = "raw2draft"

    // MARK: - Claude CLI
    static let claudeSearchPaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
    }()
}

// MARK: - Shared JSON Coders
enum JSONCoders {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - UserDefaults Keys
enum UserDefaultsKey {
    static let activeProjectId = "activeProjectId"
    static let terminalVisible = "terminalVisible"
    static let pinnedProjectIds = "pinnedProjectIds"
    static let projectsRoot = "projectsRoot"

    static let defaultAuthor = "defaultAuthor"
    static let recentWorkspaces = "recentWorkspaces"

    static func lastFile(for projectId: String) -> String {
        "lastFile_\(projectId)"
    }
}

