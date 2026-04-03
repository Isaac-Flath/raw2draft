import AppKit
import SwiftUI

/// View showing grouped list of project source files.
struct SourceFilesView: View {
    let files: [ProjectFile]
    var projectRoot: URL?

    private var groupedFiles: [(group: FileGroup, files: [ProjectFile])] {
        var groups: [FileGroup: [ProjectFile]] = [:]
        for file in files {
            groups[file.group, default: []].append(file)
        }
        return FileGroup.displayOrder.compactMap { group in
            guard let files = groups[group], !files.isEmpty else { return nil }
            return (group: group, files: files)
        }
    }

    var body: some View {
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Files")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                ForEach(groupedFiles, id: \.group) { group in
                    DisclosureGroup {
                        ForEach(group.files) { file in
                            HStack(spacing: 6) {
                                fileIcon(file)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)

                                Text(file.name)
                                    .font(.system(size: 11))
                                    .lineLimit(1)

                                Spacer()

                                if let size = file.size {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 1)
                            .contextMenu {
                                if let root = projectRoot {
                                    Button("Copy") {
                                        let url = root.appendingPathComponent(file.path)
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.writeObjects([url as NSURL])
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(group.group.label)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
            }
        }
    }

    private func fileIcon(_ file: ProjectFile) -> some View {
        Image(systemName: file.systemImageName)
    }
}
