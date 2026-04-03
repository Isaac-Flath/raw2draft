import Foundation

// MARK: - Project Stage

enum ProjectStage: String, Codable {
    case empty
    case source
    case video
    case blog
    case social
    case published
}

// MARK: - Model

struct Project: Identifiable, Codable, Equatable {
    let id: String
    let path: URL
    let hasSource: Bool
    let hasVideo: Bool
    let hasBlog: Bool
    let hasSocial: Bool
    let published: Bool
    let stage: ProjectStage

    /// Parsed parts of the project ID (format: YYYY_MM_DD_slug).
    /// Returns (year, month, day, slug) if the ID matches the expected format.
    var parsedIdParts: (year: String, month: String, day: String, slug: String)? {
        let parts = id.split(separator: "_", maxSplits: 3)
        guard parts.count == 4 else { return nil }
        return (String(parts[0]), String(parts[1]), String(parts[2]), String(parts[3]))
    }

    /// Display name derived from the directory name (strips date prefix)
    var displayName: String {
        if let parts = parsedIdParts {
            return parts.slug.replacingOccurrences(of: "-", with: " ")
        }
        return id.replacingOccurrences(of: "-", with: " ")
    }

    /// Date derived from directory name prefix
    var datePrefix: String {
        if let parts = parsedIdParts {
            return "\(parts.year)_\(parts.month)_\(parts.day)"
        }
        return ""
    }

    /// Date prefix formatted for display (e.g. "2026/01/25")
    var formattedDatePrefix: String {
        datePrefix.replacingOccurrences(of: "_", with: "/")
    }

    /// Parse a project ID string into its date prefix, if it matches YYYY_MM_DD_slug format.
    static func datePrefix(from projectId: String) -> String? {
        let parts = projectId.split(separator: "_", maxSplits: 3)
        guard parts.count == 4 else { return nil }
        return "\(parts[0])_\(parts[1])_\(parts[2])"
    }
}
