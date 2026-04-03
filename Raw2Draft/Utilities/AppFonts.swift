import SwiftUI

/// Custom font accessors for Lora (serif) and Inter (sans-serif).
/// Fonts are registered via ATSApplicationFontsPath in Info.plist.
enum AppFonts {
    // MARK: - Inter (sans-serif — headings, UI)

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold, .heavy, .black:
            return .custom("Inter-Bold", size: size)
        case .semibold, .medium:
            return .custom("Inter-Medium", size: size)
        default:
            return .custom("Inter-Regular", size: size)
        }
    }

    // MARK: - Lora (serif — body, prose)

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold, .semibold, .heavy, .black:
            return .custom("Lora-Bold", size: size)
        default:
            return .custom("Lora-Regular", size: size)
        }
    }

    // MARK: - Semantic shortcuts

    /// Title-sized Inter (e.g. sidebar "Posts", sheet headers)
    static func title(_ size: CGFloat = 20) -> Font {
        sans(size, weight: .semibold)
    }

    /// Headline-sized Inter (e.g. section headers)
    static func headline(_ size: CGFloat = 15) -> Font {
        sans(size, weight: .medium)
    }

    /// Body-sized Lora (e.g. post titles in sidebar)
    static func body(_ size: CGFloat = 14) -> Font {
        serif(size)
    }
}
