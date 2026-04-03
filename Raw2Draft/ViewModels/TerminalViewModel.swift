import Foundation
import AppKit
import GhosttyTerminal
import GhosttyKit

/// Connection status for the terminal.
enum TerminalConnectionStatus: String {
    case disconnected
    case connecting
    case connected
    case error
}

/// View model for the terminal pane.
/// Manages a pool of terminal views keyed by project ID so terminals persist across project switches.
@Observable @MainActor
final class TerminalViewModel {
    /// Per-project connection status.
    private(set) var connectionStatuses: [String: TerminalConnectionStatus] = [:]

    /// The currently active project ID.
    private(set) var activeProjectId: String?

    /// Pool of live terminal views, keyed by project ID.
    private var viewPool: [String: TerminalView] = [:]

    /// Pool of process managers, keyed by project ID.
    private var processPool: [String: TerminalProcess] = [:]

    /// Shared terminal controller with styling configuration.
    private(set) var controller: TerminalController!

    /// Computed connection status for the active project.
    var connectionStatus: TerminalConnectionStatus {
        guard let activeProjectId else { return .disconnected }
        return connectionStatuses[activeProjectId] ?? .disconnected
    }

    /// Reference to the active terminal view.
    var terminalView: TerminalView? {
        guard let activeProjectId else { return nil }
        return viewPool[activeProjectId]
    }

    /// Action bar command groups for Claude Code.
    enum ActionGroup: String, CaseIterable {
        case content
        case video
        case publish

        var commands: [ActionCommand] {
            switch self {
            case .content: return [.status, .blog, .bts, .social, .schedule]
            case .video: return [.videoEditor, .videoResolve]
            case .publish: return [.publish]
            }
        }
    }

    enum ActionCommand: String {
        case status = "/content-status"
        case blog = "/content-blog"
        case bts = "/content-bts"
        case social = "/content-social"
        case schedule = "/content-schedule"
        case videoEditor = "/video-editor"
        case videoResolve = "/video-resolve"
        case publish = "/publish"

        var label: String {
            switch self {
            case .status: return "Status"
            case .blog: return "Blog"
            case .bts: return "BTS"
            case .social: return "Social"
            case .schedule: return "Schedule"
            case .videoEditor: return "Video"
            case .videoResolve: return "Resolve"
            case .publish: return "Publish"
            }
        }
    }

    /// Working directory for terminal processes.
    var workingDirectory: URL = Constants.defaultContentPlatformRoot

    private let terminalService: any TerminalServiceProtocol
    private let keychainService: any KeychainServiceProtocol

    init(terminalService: any TerminalServiceProtocol, keychainService: any KeychainServiceProtocol) {
        self.terminalService = terminalService
        self.keychainService = keychainService
        self.controller = buildController()
    }

    // MARK: - Controller Configuration

    private func buildController() -> TerminalController {
        let palette = [
            Constants.TerminalColors.black, Constants.TerminalColors.red,
            Constants.TerminalColors.green, Constants.TerminalColors.yellow,
            Constants.TerminalColors.blue, Constants.TerminalColors.magenta,
            Constants.TerminalColors.cyan, Constants.TerminalColors.white,
            Constants.TerminalColors.brightBlack, Constants.TerminalColors.brightRed,
            Constants.TerminalColors.brightGreen, Constants.TerminalColors.brightYellow,
            Constants.TerminalColors.brightBlue, Constants.TerminalColors.brightMagenta,
            Constants.TerminalColors.brightCyan, Constants.TerminalColors.brightWhite,
        ]

        return TerminalController { builder in
            builder.withFontFamily(Constants.terminalFontName)
            builder.withFontSize(Float(Constants.terminalFontSize))
            builder.withBackground(Constants.TerminalColors.background)
            builder.withForeground(Constants.TerminalColors.foreground)
            builder.withCursorColor(Constants.TerminalColors.cursor)
            for (i, color) in palette.enumerated() {
                builder.withPalette(i, color: color)
            }
            builder.withCustom("scrollback-limit", "\(Constants.terminalScrollbackLines)")
            builder.withCustom("adjust-cell-height", "30%")
        }
    }

    // MARK: - Pool Management

    /// Set the active project. Does not create a terminal — that happens in the view layer.
    func setActiveProject(_ projectId: String?) {
        activeProjectId = projectId
    }

    /// Returns an existing terminal view for the project, or nil.
    func terminal(for projectId: String) -> TerminalView? {
        viewPool[projectId]
    }

    /// Create a new terminal view and process for a project.
    func createTerminal(for projectId: String) -> TerminalView {
        let process = TerminalProcess()
        let view = TerminalView(frame: .zero)
        view.controller = controller
        view.configuration = TerminalSurfaceOptions(
            backend: .inMemory(process.session)
        )

        viewPool[projectId] = view
        processPool[projectId] = process
        connectionStatuses[projectId] = .connecting

        // Start the child process
        let params = processParams(projectId: projectId)
        process.start(params: params)
        connectionStatuses[projectId] = .connected

        return view
    }

    /// Terminate and remove a terminal from the pool (e.g., on project deletion).
    func removeTerminal(for projectId: String) {
        processPool[projectId]?.terminate()
        processPool[projectId]?.cleanup()
        processPool.removeValue(forKey: projectId)
        viewPool[projectId]?.removeFromSuperview()
        viewPool.removeValue(forKey: projectId)
        connectionStatuses.removeValue(forKey: projectId)
    }

    // MARK: - Terminal Operations

    func copySelection() {
        // Trigger standard copy via responder chain — Ghostty handles Cmd+C natively
        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
    }

    func clearScreen() {
        guard let activeProjectId, let process = processPool[activeProjectId] else { return }
        process.sendInput("\u{1b}[2J\u{1b}[H")
    }

    func processParams(projectId: String) -> TerminalProcessParams {
        terminalService.processParams(projectId: projectId, keychainService: keychainService, workingDirectory: workingDirectory)
    }

    /// Send a command string to the running terminal as if the user typed it.
    func sendCommand(_ command: String) {
        guard let activeProjectId, let process = processPool[activeProjectId] else { return }
        process.sendInput(command + "\r")
    }

    /// Send a raw key sequence to the process for a specific project.
    func sendKeyToProcess(projectId: String, key: String) {
        processPool[projectId]?.sendInput(key)
    }

    func restartProcess(projectId: String) {
        guard viewPool[projectId] != nil else { return }

        connectionStatuses[projectId] = .connecting

        // Terminate old process
        processPool[projectId]?.terminate()
        processPool[projectId]?.cleanup()

        // Create new process and wire to existing session
        let process = TerminalProcess()
        processPool[projectId] = process

        // Update the view's backend to use the new session
        if let view = viewPool[projectId] {
            view.configuration = TerminalSurfaceOptions(
                backend: .inMemory(process.session)
            )
        }

        let params = processParams(projectId: projectId)
        process.start(params: params)
        connectionStatuses[projectId] = .connected

        // Re-establish first responder
        if let view = viewPool[projectId] {
            view.window?.makeFirstResponder(view)
        }
    }

    /// Called when a terminal process terminates.
    func handleProcessTerminated(projectId: String) {
        connectionStatuses[projectId] = .disconnected
    }
}
