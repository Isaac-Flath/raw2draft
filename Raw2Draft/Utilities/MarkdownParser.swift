import Foundation
import Markdown

/// Lightweight markdown utilities for editor styling.
/// Uses Apple's swift-markdown for robust AST-based detection.
enum MarkdownParserUtil {
    /// Detect heading level (1-6) from a line of text. Returns 0 if not a heading.
    static func headingLevel(for line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return 0 }

        var level = 0
        for char in trimmed {
            if char == "#" {
                level += 1
            } else if char == " " {
                break
            } else {
                return 0 // No space after #, not a valid heading
            }
        }
        return min(level, 6)
    }

    /// Extract image references from a line. Returns array of (alt, url) tuples.
    static func extractImageReferences(_ line: String) -> [(alt: String, url: String)] {
        let pattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsLine = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))

        return matches.map { match in
            let alt = nsLine.substring(with: match.range(at: 1))
            let url = nsLine.substring(with: match.range(at: 2))
            return (alt: alt, url: url)
        }
    }

    /// Parse a full markdown document and return structured heading info with character offsets.
    static func parseHeadings(from source: String) -> [(level: Int, text: String, characterOffset: Int)] {
        // Build a line-offset lookup table: lineNumber (1-based) → character offset
        var lineOffsets: [Int] = [0] // line 1 starts at offset 0
        for (i, char) in source.enumerated() {
            if char == "\n" {
                lineOffsets.append(i + 1)
            }
        }

        let document = Document(parsing: source)
        var headings: [(level: Int, text: String, characterOffset: Int)] = []

        for child in document.children {
            if let heading = child as? Heading {
                let text = heading.plainText
                if let range = heading.range {
                    let line = range.lowerBound.line // 1-based
                    let column = range.lowerBound.column // 1-based
                    let offset: Int
                    if line - 1 < lineOffsets.count {
                        offset = lineOffsets[line - 1] + (column - 1)
                    } else {
                        offset = 0
                    }
                    headings.append((level: heading.level, text: text, characterOffset: offset))
                }
            }
        }

        return headings
    }
}

// MARK: - Markdown Extension Helpers

private extension Heading {
    var plainText: String {
        collectText(from: children)
    }
}

/// Recursively extract text from markup nodes, handling emphasis, strong, links, etc.
private func collectText(from children: some Sequence<Markup>) -> String {
    children.map { child -> String in
        if let text = child as? Markdown.Text {
            return text.string
        }
        if let code = child as? InlineCode {
            return code.code
        }
        // Recurse into containers (emphasis, strong, links, etc.)
        return collectText(from: child.children)
    }.joined()
}
