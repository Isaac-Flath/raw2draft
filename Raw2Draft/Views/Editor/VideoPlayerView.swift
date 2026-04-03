import SwiftUI
import AVKit

/// Native AVPlayerView wrapper that bypasses the buggy _AVKit_SwiftUI framework.
private struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

/// Video player for the editor pane.
struct VideoPlayerView: View {
    let projectId: String
    let relativePath: String
    let projectService: any ProjectServiceProtocol

    @State private var player: AVPlayer?

    var body: some View {
        VStack {
            if let player {
                NativeVideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Video not available")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            loadVideo()
        }
        .onChange(of: relativePath) {
            loadVideo()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func loadVideo() {
        let projectRoot = projectService.resolveProjectRoot(projectId)
        guard let resolved = PathSanitizer.resolveSafe(root: projectRoot, relativePath: relativePath) else { return }
        player = AVPlayer(url: resolved)
    }
}
