import Foundation

extension URL {
    /// Create a ProjectFile from this URL with the given group, using the URL's path and filename.
    func toProjectFile(group: FileGroup = .content) -> ProjectFile {
        ProjectFile(
            path: path,
            name: lastPathComponent,
            group: group,
            size: nil,
            modified: nil
        )
    }
}
