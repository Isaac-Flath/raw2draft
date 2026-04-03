import SwiftUI

/// Image preview for the editor pane.
struct ImagePreviewView: View {
    let projectId: String
    let relativePath: String
    let projectService: any ProjectServiceProtocol

    @State private var nsImage: NSImage?

    var body: some View {
        ScrollView {
            VStack {
                if let image = nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 800)
                        .padding()
                } else {
                    ProgressView()
                        .padding()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: relativePath) {
            loadImage()
        }
    }

    private func loadImage() {
        let projectRoot = projectService.resolveProjectRoot(projectId)
        guard let resolved = PathSanitizer.resolveSafe(root: projectRoot, relativePath: relativePath) else { return }
        nsImage = NSImage(contentsOf: resolved)
    }
}
