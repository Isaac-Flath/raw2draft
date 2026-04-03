import Foundation

// MARK: - URL Status

enum URLStatus: String, Codable {
    case pending
    case processing
    case processed
    case error
}

// MARK: - URL Type

enum URLType: String, Codable {
    case youtube
    case pdf
    case webpage
    case unknown
}

// MARK: - Models

struct SourceURL: Identifiable, Codable, Equatable {
    var id: String { url }
    let url: String
    let type: URLType
    var status: URLStatus
    var addedAt: Date?
    var updatedAt: Date?
}

struct SourcesFile: Codable {
    var urls: [SourceURL]
}
