import SwiftUI
import UniformTypeIdentifiers

/// Drag-and-drop zone for uploading source files.
struct DropZoneView: View {
    let onUploadFile: (URL) -> Void
    let onFilesUploaded: () -> Void

    @State private var isTargeted = false
    @State private var uploadMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(isTargeted ? AppColors.purple.opacity(0.7) : .secondary)

            Group {
                if let message = uploadMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(message.hasPrefix("Error") ? AppColors.statusError : AppColors.success)
                        .transition(.opacity)
                } else {
                    Text("Drop files here to add as source")
                        .font(.system(size: 12))
                        .foregroundStyle(isTargeted ? AppColors.purple.opacity(0.7) : .secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: uploadMessage)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? AppColors.purple.opacity(0.5) : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 3])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isTargeted ? AppColors.purple.opacity(0.04) : Color.clear)
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                DispatchQueue.main.async {
                    onUploadFile(url)
                    onFilesUploaded()
                }
            }
        }
    }
}
