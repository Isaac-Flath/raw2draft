import Foundation
import os

private let logger = Logger(subsystem: "com.raw2draft", category: "SourcesViewModel")

/// View model for the sources section.
@Observable @MainActor
final class SourcesViewModel: ErrorHandling {
    var urlInput: String = ""
    var textFilename: String = ""
    var textContent: String = ""
    var isExpanded: Bool = true
    var sourceUrls: [SourceURL] = []
    var uploadProgress: Double?
    var uploadStatus: String?
    var errorMessage: String?

    private let projectService: any ProjectServiceProtocol

    init(projectService: any ProjectServiceProtocol) {
        self.projectService = projectService
    }

    func loadSourceUrls(projectId: String) {
        do {
            let sources = try projectService.getSourceUrls(projectId: projectId)
            sourceUrls = sources.urls
        } catch {
            logger.warning("Failed to load source URLs for '\(projectId)': \(error.localizedDescription)")
            sourceUrls = []
        }
    }

    func addUrl(projectId: String) {
        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        do {
            let sources = try projectService.addSourceUrl(projectId: projectId, url: url, type: .unknown)
            sourceUrls = sources.urls
            urlInput = ""
        } catch {
            showError(error.localizedDescription)
        }
    }

    func removeUrl(_ url: String, projectId: String) {
        do {
            let sources = try projectService.removeSourceUrl(projectId: projectId, url: url)
            sourceUrls = sources.urls
        } catch {
            showError(error.localizedDescription)
        }
    }

    func uploadSourceFile(from url: URL, projectId: String) {
        let filename = url.lastPathComponent
        guard let fileData = try? Data(contentsOf: url) else {
            uploadStatus = "Error: Could not read \(filename)"
            return
        }

        do {
            _ = try projectService.uploadSourceFile(
                projectId: projectId,
                filename: filename,
                data: fileData
            )
            uploadStatus = "Uploaded \(filename)"
        } catch {
            uploadStatus = "Error: \(error.localizedDescription)"
        }
    }

    func saveTextSource(projectId: String) {
        let filename = textFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filename.isEmpty, !content.isEmpty else { return }

        let finalFilename = filename.hasSuffix(".md") ? filename : "\(filename).md"

        do {
            try projectService.writeProjectFile(
                projectId: projectId,
                relativePath: "source/\(finalFilename)",
                content: content
            )
            textFilename = ""
            textContent = ""
        } catch {
            showError(error.localizedDescription)
        }
    }
}
