import Foundation

/// View model for the settings sheet.
@Observable @MainActor
final class SettingsViewModel: ErrorHandling {
    var envText: String = ""
    var errorMessage: String?
    var saveConfirmation: String?
    var envFilePath: String = ""

    private let envFileService: any EnvFileServiceProtocol

    init(envFileService: any EnvFileServiceProtocol) {
        self.envFileService = envFileService
        self.envFilePath = envFileService.envFileURL.path
    }

    func loadStatuses() {
        envText = envFileService.readEnvFile()
    }

    func saveEnvText() {
        do {
            try envFileService.writeEnvFile(envText)
            saveConfirmation = "Saved"
            // Reload to reflect actual state
            envText = envFileService.readEnvFile()
        } catch {
            showError(error.localizedDescription)
        }
    }
}
