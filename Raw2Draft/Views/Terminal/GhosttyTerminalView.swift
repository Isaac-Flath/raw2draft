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

        /// Monitor terminal key events and forward them to the PTY directly.
        /// libghostty's InMemoryTerminalSession routes some AppKit keys directly,
        /// but Raw2Draft needs consistent text input and modifier-aware Enter.
        private func installKeyMonitor(terminalView: TerminalView) {
            removeKeyMonitor()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak terminalView] event in
                guard let self, let terminalView, let projectId = self.currentProjectId else { return event }
                // Only intercept when the terminal view is first responder
                guard terminalView.window?.firstResponder === terminalView else { return event }

                // Handle ⌘V paste directly into the terminal
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        self.sendKeyToProcess(projectId: projectId, key: text)
                    }
                    return nil
                }

                // Let other ⌘-modified keys reach the menu system instead of Ghostty
                if event.modifierFlags.contains(.command) {
                    DispatchQueue.main.async {
                        NSApp.mainMenu?.performKeyEquivalent(with: event)
                    }
                    return nil
                }

                if let sequence = self.terminalInputSequence(for: event) {
                    self.sendKeyToProcess(projectId: projectId, key: sequence)
                    return nil
                }

                return event
            }
        }

        private func sendKeyToProcess(projectId: String, key: String) {
            MainActor.assumeIsolated {
                parent.terminalViewModel.sendKeyToProcess(projectId: projectId, key: key)
            }
        }

        private func terminalInputSequence(for event: NSEvent) -> String? {
            let keyCode = event.keyCode

            // Return = 36, Enter (numpad) = 76
            if keyCode == 36 || keyCode == 76 {
                if let modifier = csiModifierParameter(for: event) {
                    return "\u{1b}[13;\(modifier)u"
                }
                return "\r"
            }

            // Tab = 48
            if keyCode == 48 {
                return event.modifierFlags.contains(.shift) ? "\u{1b}[Z" : "\t"
            }

            // Escape = 53
            if keyCode == 53 {
                return "\u{1b}"
            }

            // Backspace = 51
            if keyCode == 51 {
                if event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.control) {
                    return "\u{1b}\u{7f}"
                }
                return "\u{7f}"
            }

            switch keyCode {
            case 123: return cursorSequence("D", event: event) // Left
            case 124: return cursorSequence("C", event: event) // Right
            case 125: return cursorSequence("B", event: event) // Down
            case 126: return cursorSequence("A", event: event) // Up
            case 115: return cursorSequence("H", event: event) // Home
            case 119: return cursorSequence("F", event: event) // End
            case 116: return tildeSequence(5, event: event) // Page Up
            case 121: return tildeSequence(6, event: event) // Page Down
            case 117: return tildeSequence(3, event: event) // Forward Delete
            default: break
            }

            return printableText(for: event)
        }

        private func printableText(for event: NSEvent) -> String? {
            guard event.modifierFlags.intersection([.command, .control]).isEmpty else {
                return nil
            }
            guard let characters = event.characters, !characters.isEmpty else {
                return nil
            }
            guard !isPrivateUseFunctionKey(characters) else {
                return nil
            }
            return characters
        }

        private func cursorSequence(_ finalByte: String, event: NSEvent) -> String {
            if let modifier = csiModifierParameter(for: event) {
                return "\u{1b}[1;\(modifier)\(finalByte)"
            }
            return "\u{1b}[\(finalByte)"
        }

        private func tildeSequence(_ code: Int, event: NSEvent) -> String {
            if let modifier = csiModifierParameter(for: event) {
                return "\u{1b}[\(code);\(modifier)~"
            }
            return "\u{1b}[\(code)~"
        }

        private func csiModifierParameter(for event: NSEvent) -> Int? {
            var modifier = 1
            if event.modifierFlags.contains(.shift) { modifier += 1 }
            if event.modifierFlags.contains(.option) { modifier += 2 }
            if event.modifierFlags.contains(.control) { modifier += 4 }
            return modifier == 1 ? nil : modifier
        }

        private func isPrivateUseFunctionKey(_ characters: String) -> Bool {
            guard characters.count == 1,
                  let scalar = characters.unicodeScalars.first
            else {
                return false
            }
            return (0xF700...0xF8FF).contains(Int(scalar.value))
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
