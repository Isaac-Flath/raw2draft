import Foundation

/// View model for the settings sheet.
@Observable @MainActor
final class SettingsViewModel: ErrorHandling {
    var envText: String = ""
    var errorMessage: String?
    var saveConfirmation: String?
    var envFilePath: String = ""

    private let keychainService: any KeychainServiceProtocol

    init(keychainService: any KeychainServiceProtocol) {
        self.keychainService = keychainService
        self.envFilePath = keychainService.envFileURL.path
    }

    func loadStatuses() {
        envText = keychainService.readEnvFile()
    }

    func saveEnvText() {
        do {
            try keychainService.writeEnvFile(envText)
            saveConfirmation = "Saved"
            // Reload to reflect actual state
            envText = keychainService.readEnvFile()
        } catch {
            showError(error.localizedDescription)
        }
    }
}
