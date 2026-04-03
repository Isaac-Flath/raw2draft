import Foundation

/// Post lifecycle status.
enum PostStatus: String {
    case draft
    case scheduled
    case published
}

/// Represents a blog post parsed from posts/.
struct BlogPost: Identifiable {
    let id: String           // filename
    let filePath: URL
    let title: String
    let date: String
    let section: String
    let subsection: String
    let isDraft: Bool
    let project: String?     // linked project directory name
    let wordCount: Int
    let lastModified: Date?  // file system modification date
    let access: String       // "members" for extras posts, "" for regular

    var slug: String {
        var name = filePath.deletingLastPathComponent().lastPathComponent
        if let range = name.range(of: #"^\d{4}-\d{2}-\d{2}-"#, options: .regularExpression) {
            name = String(name[range.upperBound...])
        }
        return name
    }

    var publicURL: String {
        let base = UserDefaults.standard.string(forKey: "publicURLBase") ?? ""
        guard !base.isEmpty else { return slug }
        return "\(base)/\(slug)"
    }

    var status: PostStatus {
        if isDraft { return .draft }
        // Check if date is in the future
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let postDate = formatter.date(from: date), postDate > Date() {
            return .scheduled
        }
        return .published
    }
}

/// Parses blog posts from the posts/ directory.
enum BlogPostParser {
    static func loadPosts(from postsDirectory: URL) -> [BlogPost] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: postsDirectory.path) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(
            at: postsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var postFiles: [URL] = []

        for url in contents {
            // Each post is a directory containing blog.md
            let blogMd = url.appendingPathComponent("blog.md")
            if fm.fileExists(atPath: blogMd.path) {
                postFiles.append(blogMd)
            }
        }

        return postFiles.compactMap { url in
            parseFrontmatter(at: url)
        }.sorted { $0.date > $1.date }
    }

    private static func parseFrontmatter(at url: URL) -> BlogPost? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let postId = url.deletingLastPathComponent().lastPathComponent
        let lastModified = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return BlogPost(
                id: postId,
                filePath: url,
                title: url.deletingPathExtension().lastPathComponent,
                date: "",
                section: "",
                subsection: "",
                isDraft: false,
                project: nil,
                wordCount: content.split(whereSeparator: \.isWhitespace).count,
                lastModified: lastModified,
                access: ""
            )
        }

        // Find closing ---
        var endIndex = -1
        for i in 1..<min(lines.count, 50) {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }

        guard endIndex > 0 else { return nil }

        let frontmatter = lines[1..<endIndex].joined(separator: "\n")
        let body = lines[(endIndex + 1)...].joined(separator: "\n")

        func extractValue(_ key: String) -> String {
            let pattern = #"(?m)^\s*"# + key + #"\s*:\s*"?([^"\n]*)"?\s*$"#
            guard let range = frontmatter.range(of: pattern, options: .regularExpression) else { return "" }
            let match = String(frontmatter[range])
            // Extract value after colon
            if let colonRange = match.range(of: ":") {
                var value = String(match[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                // Remove surrounding quotes
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                return value
            }
            return ""
        }

        let draftValue = extractValue("draft").lowercased()
        let isDraft = draftValue == "true"

        let projectValue = extractValue("project")

        return BlogPost(
            id: postId,
            filePath: url,
            title: extractValue("title"),
            date: extractValue("date"),
            section: extractValue("section"),
            subsection: extractValue("subsection"),
            isDraft: isDraft,
            project: projectValue.isEmpty ? nil : projectValue,
            wordCount: body.split(whereSeparator: \.isWhitespace).count,
            lastModified: lastModified,
            access: extractValue("access")
        )
    }
}
