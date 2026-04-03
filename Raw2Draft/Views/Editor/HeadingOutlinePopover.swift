import SwiftUI

/// Popover showing document heading outline for quick navigation.
struct HeadingOutlinePopover: View {
    let headings: [(level: Int, text: String, characterOffset: Int)]
    let onSelect: (Int, Int) -> Void  // (characterOffset, headingIndex)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if headings.isEmpty {
                Text("No headings found")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(headings.enumerated()), id: \.offset) { index, heading in
                            Button {
                                onSelect(heading.characterOffset, index)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(headingPrefix(level: heading.level))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, alignment: .trailing)

                                    Text(heading.text)
                                        .font(AppFonts.sans(fontSize(for: heading.level), weight: weight(for: heading.level)))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .padding(.leading, indentation(for: heading.level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 400)
    }

    private func headingPrefix(level: Int) -> String {
        String(repeating: "#", count: level)
    }

    private func indentation(for level: Int) -> CGFloat {
        CGFloat((level - 1) * 12)
    }

    private func fontSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 14
        case 2: return 13
        default: return 12
        }
    }

    private func weight(for level: Int) -> Font.Weight {
        level <= 2 ? .semibold : .regular
    }
}
