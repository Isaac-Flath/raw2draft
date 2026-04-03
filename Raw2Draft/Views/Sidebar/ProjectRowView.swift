import SwiftUI

/// A single project row in the sidebar.
struct ProjectRowView: View {
    let project: Project
    let isActive: Bool
    let isPinned: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onReveal: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                stageIndicator

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(project.displayName)
                            .font(AppFonts.sans(13, weight: .medium))
                            .lineLimit(1)

                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(project.formattedDatePrefix)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? AppColors.warmTintActive : (isHovered ? AppColors.warmTint : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                onRename()
            } label: {
                Label("Rename...", systemImage: "pencil")
            }

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            Button {
                onReveal()
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Button {
                onTogglePin()
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var stageIndicator: some View {
        let (color, icon) = stageInfo
        Image(systemName: icon)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .frame(width: 20)
    }

    private var stageInfo: (Color, String) {
        switch project.stage {
        case .empty:
            return (AppColors.stageEmpty, "folder")
        case .source:
            return (AppColors.stageSource, "doc.text")
        case .video:
            return (AppColors.stageVideo, "film")
        case .blog:
            return (AppColors.stageBlog, "doc.richtext")
        case .social:
            return (AppColors.stageSocial, "square.stack")
        case .published:
            return (AppColors.stagePublished, "checkmark.circle.fill")
        }
    }
}
