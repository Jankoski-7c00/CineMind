import AppKit
import AVKit
import PlaybackAVFoundation
import SwiftUI

struct PlaybackAVFoundationSurfaceView: NSViewRepresentable {
    let backend: AVFoundationPlaybackBackend

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView(frame: .zero)
        configure(playerView)
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        configure(nsView)
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player = nil
    }

    private func configure(_ playerView: AVPlayerView) {
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.player = backend.player
    }
}
