import SwiftUI
import AppKit

// MARK: - Shared Hex Parsing

/// Parse a hex color string into (red, green, blue, alpha) components in 0...1.
/// Supports 3-digit (#RGB), 6-digit (#RRGGBB), and 8-digit (#AARRGGBB) hex strings.
func parseHexColor(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch hex.count {
    case 3:
        (a, r, g, b) = (255, ((int >> 8) & 0xF) * 17, ((int >> 4) & 0xF) * 17, (int & 0xF) * 17)
    case 6:
        (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8:
        (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default:
        (a, r, g, b) = (255, 0, 0, 0)
    }
    return (CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, CGFloat(a) / 255)
}

// MARK: - SwiftUI Color hex initializer

extension Color {
    init(hex: String) {
        let c = parseHexColor(hex)
        self.init(.sRGB, red: Double(c.r), green: Double(c.g), blue: Double(c.b), opacity: Double(c.a))
    }
}

// MARK: - NSColor hex initializer

extension NSColor {
    convenience init(hex: String) {
        let c = parseHexColor(hex)
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    /// Create an adaptive color that switches between light and dark variants.
    static func adaptive(light: String, dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(hex: dark)
            }
            return NSColor(hex: light)
        }
    }
}

// MARK: - Adaptive Editor Colors

enum EditorColors {
    static let background: NSColor = .adaptive(light: "#faf5ff", dark: "#1c1917")
    static let currentLine: NSColor = .adaptive(light: "#f0ebff", dark: "#292524")
    static let syntaxDim: NSColor = .adaptive(light: "#a5b4c4", dark: "#57534e")
    static let blockquoteText: NSColor = .adaptive(light: "#6b7280", dark: "#a8a29e")
    static let blockquoteBorder: NSColor = .adaptive(light: "#4f46e5", dark: "#818cf8")
    static let codeSpan: NSColor = .adaptive(light: "#7c3aed", dark: "#a78bfa")
    static let link: NSColor = .adaptive(light: "#4f46e5", dark: "#818cf8")
    static let imageSyntax: NSColor = .adaptive(light: "#9ca3af", dark: "#78716c")
}

// MARK: - App Theme Colors

enum AppColors {
    // Backgrounds
    static let sidebarBackground = Color(hex: "#faf9fb")
    static let editorBackground = Color(hex: "#faf9fb")
    static let controlBackground = Color(hex: "#efe9f8")

    // Accents
    static let indigo = Color(hex: "#4f46e5")
    static let purple = Color(hex: "#9333ea")
    static let gold = Color(hex: "#eab308")

    // Neutral tints for interactive states (replace indigo highlights)
    static let warmTint = Color(hex: "#f5f0fa")       // barely-there hover
    static let warmTintActive = Color(hex: "#ede5f5")  // subtle active state

    // Brand gradients
    static let brandGradient = LinearGradient(
        colors: [Color(hex: "#4f46e5"), Color(hex: "#9333ea")],
        startPoint: .leading, endPoint: .trailing
    )
    static let brandDivider = LinearGradient(
        colors: [Color(hex: "#4f46e5"), Color(hex: "#9333ea"), Color(hex: "#22d3ee")],
        startPoint: .leading, endPoint: .trailing
    )

    // Status
    static let success = Color(hex: "#059669")
    static let statusError = Color(hex: "#dc2626")
    static let errorBackground = Color(hex: "#dc2626")

    // Cloud status
    static let statusConnected = Color(hex: "#059669")
    static let statusDisconnected = Color.gray

    // Stage indicators
    static let stageEmpty = Color.gray
    static let stageSource = Color(hex: "#4f46e5")
    static let stageVideo = Color(hex: "#dc2626")
    static let stageBlog = Color(hex: "#eab308")
    static let stageSocial = Color(hex: "#9333ea")
    static let stagePublished = Color(hex: "#059669")
}
