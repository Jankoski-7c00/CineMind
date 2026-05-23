import AppKit
import Foundation
import LibMPVPlayback
import SwiftUI

struct PlaybackOpenGLRenderSurfaceView: NSViewRepresentable {
    let backend: LibMPVPlaybackBackend

    func makeCoordinator() -> Coordinator {
        Coordinator(backend: backend)
    }

    func makeNSView(context: Context) -> NSOpenGLView {
        guard let view = RenderOpenGLView(frame: .zero, pixelFormat: Self.makePixelFormat()) else {
            fatalError("Failed to create playback render surface")
        }

        view.renderAfterSurfaceChange = { [weak coordinator = context.coordinator] in
            coordinator?.renderSurfaceNow()
        }

        context.coordinator.attachAndPrepare(view)
        return view
    }

    func updateNSView(_ nsView: NSOpenGLView, context: Context) {}

    static func dismantleNSView(_ nsView: NSOpenGLView, coordinator: Coordinator) {
        if let renderView = nsView as? RenderOpenGLView {
            renderView.renderAfterSurfaceChange = nil
        }
        coordinator.cancelPreparation()
    }

    private static func makePixelFormat() -> NSOpenGLPixelFormat {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAAccelerated),
            0
        ]

        guard let pixelFormat = NSOpenGLPixelFormat(attributes: attributes) else {
            fatalError("Failed to create NSOpenGLPixelFormat")
        }

        return pixelFormat
    }
}

extension PlaybackOpenGLRenderSurfaceView {
    final class Coordinator {
        private let backend: LibMPVPlaybackBackend
        private var prepareTask: Task<Void, Never>?

        init(backend: LibMPVPlaybackBackend) {
            self.backend = backend
        }

        @MainActor
        fileprivate func attachAndPrepare(_ view: RenderOpenGLView) {
            do {
                try backend.attachRenderSurface(view)
            } catch {
                writePlaybackRenderWarning("Could not attach playback render surface: \(error)")
                return
            }

            prepareTask?.cancel()
            prepareTask = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                do {
                    try await backend.prepareRenderSurface()
                    guard !Task.isCancelled else {
                        return
                    }
                    backend.renderSurfaceNow()
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }
                    writePlaybackRenderWarning("Could not prepare playback render surface: \(error)")
                }
            }
        }

        @MainActor
        func renderSurfaceNow() {
            backend.renderSurfaceNow()
        }

        func cancelPreparation() {
            prepareTask?.cancel()
            prepareTask = nil
        }
    }
}

private final class RenderOpenGLView: NSOpenGLView {
    var renderAfterSurfaceChange: (() -> Void)?

    override func reshape() {
        super.reshape()
        openGLContext?.update()
        renderAfterSurfaceChange?()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        openGLContext?.update()
        renderAfterSurfaceChange?()
    }
}

private func writePlaybackRenderWarning(_ message: String) {
    FileHandle.standardError.write(Data(("Warning: " + message + "\n").utf8))
}
