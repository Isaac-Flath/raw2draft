import AppKit

/// AppDelegate for single-instance enforcement, file open handling, and window configuration.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let openFilePath = "/tmp/raw2draft-open"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force light appearance for consistent lavender theme
        NSApp.appearance = NSAppearance(named: .aqua)

        // Deploy bundled Claude context (skills, references, CLAUDE.md)
        ClaudeContextDeployer.deploy()

        // Single-instance enforcement
        let bundleId = Bundle.main.bundleIdentifier ?? "com.isaac-flath.Raw2Draft"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if running.count > 1 {
            if let existing = running.first(where: { $0 != NSRunningApplication.current }) {
                existing.activate()
            }
            NSApp.terminate(nil)
            return
        }

        // Check for path from `draft` CLI
        checkForDraftOpen()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Set window frame autosave name for state restoration
        if let window = NSApp.windows.first, window.frameAutosaveName.isEmpty {
            window.setFrameAutosaveName("Raw2DraftMainWindow")
        }

        // Check for path from `draft` CLI (handles re-activation of running app)
        checkForDraftOpen()
    }

    /// Handle files opened via Finder (double-click, drag to dock icon, open command).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        NotificationCenter.default.post(
            name: .openFileOrDirectory,
            object: nil,
            userInfo: ["url": url]
        )
    }

    /// Read and consume the temp file written by the `draft` CLI.
    private func checkForDraftOpen() {
        let path = Self.openFilePath
        guard FileManager.default.fileExists(atPath: path),
              let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Consume the file immediately so we don't re-open on next activation
        try? FileManager.default.removeItem(atPath: path)

        let url = URL(fileURLWithPath: trimmed)
        NotificationCenter.default.post(
            name: .openFileOrDirectory,
            object: nil,
            userInfo: ["url": url]
        )
    }
}

extension Notification.Name {
    static let openFileOrDirectory = Notification.Name("openFileOrDirectory")
}
