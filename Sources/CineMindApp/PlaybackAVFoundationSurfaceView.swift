import AppKit
import AVKit
import PlaybackAVFoundation
import SwiftUI

final class PassiveAVPlayerView: AVPlayerView {
    override var acceptsFirstResponder: Bool {
        false
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        nextResponder?.keyDown(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func mouseDown(with event: NSEvent) {}

    override func rightMouseDown(with event: NSEvent) {}

    override func otherMouseDown(with event: NSEvent) {}
}

struct PlaybackAVFoundationSurfaceView: NSViewRepresentable {
    let backend: AVFoundationPlaybackBackend

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = PassiveAVPlayerView(frame: .zero)
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
