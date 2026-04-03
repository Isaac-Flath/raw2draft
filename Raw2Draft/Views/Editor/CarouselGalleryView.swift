import SwiftUI

/// Grid gallery view for carousel images.
struct CarouselGalleryView: View {
    let projectId: String
    let images: [ProjectFile]
    let projectService: any ProjectServiceProtocol

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(images) { file in
                    carouselImage(file: file)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func carouselImage(file: ProjectFile) -> some View {
        let projectRoot = projectService.resolveProjectRoot(projectId)
        if let resolved = PathSanitizer.resolveSafe(root: projectRoot, relativePath: file.path),
           let nsImage = NSImage(contentsOf: resolved) {
            VStack(spacing: 4) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)

                Text(file.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
