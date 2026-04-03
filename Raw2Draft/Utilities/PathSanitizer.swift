import Foundation

enum PathSanitizer {
    /// Resolve a relative path within a root directory, ensuring it doesn't escape.
    /// Returns the resolved URL or nil if the path would escape the root.
    static func resolveSafe(root: URL, relativePath: String) -> URL? {
        let resolved = root.appendingPathComponent(relativePath).standardized
        let rootPath = root.standardized.path
        let resolvedPath = resolved.path

        guard resolvedPath.hasPrefix(rootPath + "/") || resolvedPath == rootPath else {
            return nil
        }
        return resolved
    }

    /// Sanitize a filename by removing directory components and dangerous characters.
    static func sanitizeFilename(_ filename: String) -> String? {
        let basename = (filename as NSString).lastPathComponent
        guard !basename.isEmpty, basename != ".", basename != ".." else {
            return nil
        }
        return basename
    }

    /// Sanitize a project name into a URL-safe slug.
    static func slugify(_ name: String) -> String? {
        let sanitized = name
            .lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9]+",
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return sanitized.isEmpty ? nil : sanitized
    }
}
