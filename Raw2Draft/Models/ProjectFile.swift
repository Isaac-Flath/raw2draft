import Foundation

// MARK: - File Group

enum FileGroup: String, Codable, CaseIterable {
    case source
    case content
    case social
    case screenshots
    case images
    case video

    /// Canonical display ordering used across the app.
    static let displayOrder: [FileGroup] = [.source, .video, .content, .social, .images, .screenshots]

    /// Human-readable label.
    var label: String {
        rawValue.capitalized
    }
}

// MARK: - File Type

enum FileType: Equatable {
    case video
    case image
    case markdown
    case other
}

struct ProjectFile: Identifiable, Codable, Equatable {
    var id: String { path }
    let path: String
    let name: String
    let group: FileGroup
    let size: Int?
    let modified: Date?

    /// File extension (lowercase, no dot)
    var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    var fileType: FileType {
        if Constants.videoExtensions.contains(fileExtension) { return .video }
        if Constants.imageExtensions.contains(fileExtension) { return .image }
        if Constants.markdownExtensions.contains(fileExtension) { return .markdown }
        return .other
    }

    var isVideo: Bool { fileType == .video }
    var isImage: Bool { fileType == .image }
    var isMarkdown: Bool { fileType == .markdown }

    var systemImageName: String {
        switch fileType {
        case .markdown: return "doc.text"
        case .image: return "photo"
        case .video: return "film"
        case .other: return "doc"
        }
    }
}
