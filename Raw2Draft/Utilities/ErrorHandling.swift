import Foundation

/// Protocol for ViewModels that surface error messages.
///
/// Adopters must declare `var errorMessage: String?` (the protocol cannot
/// require the `@Observable` macro to track it, so each conforming class
/// keeps its own stored property). The protocol supplies a default
/// `showError(_:autoDismiss:)` implementation that optionally clears the
/// message after a delay.
@MainActor
protocol ErrorHandling: AnyObject {
    var errorMessage: String? { get set }
}

extension ErrorHandling {
    /// Set an error message, optionally auto-dismissing it after `seconds`.
    /// - Parameters:
    ///   - message: The error text to display.
    ///   - autoDismiss: If non-nil, the message is cleared after this many seconds
    ///     (only if it hasn't been replaced in the meantime).
    func showError(_ message: String, autoDismiss seconds: TimeInterval? = nil) {
        errorMessage = message

        if let seconds {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                if self?.errorMessage == message {
                    self?.errorMessage = nil
                }
            }
        }
    }
}
