import SwiftUI
import AppKit
import GhosttyTerminal

/// NSViewRepresentable that manages a pool of libghostty terminal views, swapping the visible one
/// when the active project changes. Terminals persist across project switches.
struct GhosttyTerminalView: NSViewRepresentable {
    let projectId: String
    @Bindable var terminalViewModel: TerminalViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        context.coordinator.attachTerminal(to: container, projectId: projectId)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attachTerminal(to: container, projectId: projectId)
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        coordinator.removeKeyMonitor()
        for subview in container.subviews {
            subview.removeFromSuperview()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var parent: GhosttyTerminalView
        private var currentProjectId: String?
        private var keyMonitor: Any?

        init(parent: GhosttyTerminalView) {
            self.parent = parent
        }

        @MainActor
        func attachTerminal(to container: NSView, projectId: String) {
            parent.terminalViewModel.setActiveProject(projectId)

            guard projectId != currentProjectId else { return }
            currentProjectId = projectId

            // Remove old terminal from container (but don't destroy it)
            for subview in container.subviews {
                subview.removeFromSuperview()
            }

            // Get existing or create new terminal
            let terminalView: TerminalView
            if let existing = parent.terminalViewModel.terminal(for: projectId) {
                terminalView = existing
            } else {
                terminalView = parent.terminalViewModel.createTerminal(for: projectId)
            }

            // Add to container with autolayout
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(terminalView)
            NSLayoutConstraint.activate([
                terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                terminalView.topAnchor.constraint(equalTo: container.topAnchor),
                terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            // Make first responder for keyboard input
            DispatchQueue.main.async {
                container.window?.makeFirstResponder(terminalView)
            }

            installKeyMonitor(terminalView: terminalView)
        }

        /// Monitor for Enter/Return key events and forward them to the PTY directly.
        /// libghostty's InMemoryTerminalSession may not forward non-printable keys
        /// through the write callback, so we intercept Enter at the NSEvent level.
        private func installKeyMonitor(terminalView: TerminalView) {
            removeKeyMonitor()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak terminalView] event in
                guard let self, let terminalView, let projectId = self.currentProjectId else { return event }
                // Only intercept when the terminal view is first responder
                guard terminalView.window?.firstResponder === terminalView else { return event }

                let keyCode = event.keyCode
                // Return = 36, Enter (numpad) = 76
                if keyCode == 36 || keyCode == 76 {
                    self.parent.terminalViewModel.sendKeyToProcess(projectId: projectId, key: "\r")
                    return nil // consume the event
                }
                // Tab = 48
                if keyCode == 48 {
                    self.parent.terminalViewModel.sendKeyToProcess(projectId: projectId, key: "\t")
                    return nil
                }
                // Escape = 53
                if keyCode == 53 {
                    self.parent.terminalViewModel.sendKeyToProcess(projectId: projectId, key: "\u{1b}")
                    return nil
                }
                // Backspace = 51
                if keyCode == 51 {
                    self.parent.terminalViewModel.sendKeyToProcess(projectId: projectId, key: "\u{7f}")
                    return nil
                }
                // Arrow keys: Up=126, Down=125, Left=123, Right=124
                switch keyCode {
                case 126: self.parent.terminalViewModel.sendKeyToProcess(projectId: projectId, key: "\u{1b}[A"); return nil
                case 125: self.parent.terminalViewModel.sendKeyToProcess(projectId: projectId, key: "\u{1b}[B"); return nil
                case 124: self.parent.terminalViewModel.sendKeyToProcess(projectId: projectId, key: "\u{1b}[C"); return nil
                case 123: self.parent.terminalViewModel.sendKeyToProcess(projectId: projectId, key: "\u{1b}[D"); return nil
                default: break
                }

                return event
            }
        }

        func removeKeyMonitor() {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }

        deinit {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
