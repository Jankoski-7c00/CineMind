@preconcurrency import AppKit
import Darwin
import Foundation
import Playback

private let MPV_RENDER_PARAM_INVALID: Int32 = 0
private let MPV_RENDER_PARAM_API_TYPE: Int32 = 1
private let MPV_RENDER_PARAM_OPENGL_INIT_PARAMS: Int32 = 2
private let MPV_RENDER_PARAM_OPENGL_FBO: Int32 = 3
private let MPV_RENDER_PARAM_FLIP_Y: Int32 = 4

private typealias MPVOpenGLGetProcAddress = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer?

private struct MPVRenderParam {
    var type: Int32
    var data: UnsafeMutableRawPointer?
}

private struct MPVOpenGLInitParams {
    var get_proc_address: MPVOpenGLGetProcAddress?
    var get_proc_address_ctx: UnsafeMutableRawPointer?
    var extra_exts: UnsafePointer<CChar>?
}

private struct MPVOpenGLFBO {
    var fbo: Int32
    var w: Int32
    var h: Int32
    var internal_format: Int32
}

// Spike-only adapter for rendering libmpv into an AppKit-owned NSOpenGLView.
final class MPVOpenGLRenderAdapter: @unchecked Sendable {
    private weak var openGLView: NSOpenGLView?
    private let runtime: MPVRuntime
    private let lock = NSLock()

    private var renderAPI: MPVRenderAPI?
    private var renderContext: UnsafeMutableRawPointer?
    private var openGLLibrary: UnsafeMutableRawPointer?
    private var missingOpenGLProcName: String?
    private var isPreparing = false
    private var isRenderScheduled = false
    private var isShuttingDown = false
    private var hasLoggedRenderError = false

    @MainActor
    init(openGLView: NSOpenGLView, runtime: MPVRuntime) {
        self.openGLView = openGLView
        self.runtime = runtime
    }

    @MainActor
    func prepare() async throws {
        if renderContext != nil {
            return
        }

        guard !readShuttingDown() else {
            throw PlaybackError.invalidState("spike render surface has already shut down")
        }

        guard !isPreparing else {
            throw PlaybackError.invalidState("spike render surface preparation is already in progress")
        }

        guard let openGLView, let openGLContext = openGLView.openGLContext else {
            throw PlaybackError.mpvError("spike render surface is missing an OpenGL context")
        }

        isPreparing = true
        defer {
            isPreparing = false
        }

        openGLContext.makeCurrentContext()
        openGLContext.update()

        if openGLLibrary == nil {
            openGLLibrary = try Self.openOpenGLLibrary()
        }

        do {
            let createdContext = try await runtime.withRenderCore { core in
                try self.createRenderContext(core: core)
            }
            renderAPI = createdContext.renderAPI
            renderContext = createdContext.context
            createdContext.renderAPI.setUpdateCallback(
                context: createdContext.context,
                callback: mpvRenderUpdateCallback,
                callbackContext: callbackContext
            )
            renderNow()
        } catch {
            if renderContext == nil, let openGLLibrary {
                dlclose(openGLLibrary)
                self.openGLLibrary = nil
            }
            throw error
        }
    }

    @MainActor
    func renderNow() {
        guard let renderContext, let renderAPI else {
            return
        }

        guard !readShuttingDown() else {
            return
        }

        guard let openGLView, let openGLContext = openGLView.openGLContext else {
            return
        }

        let backingBounds = openGLView.convertToBacking(openGLView.bounds)
        let width = max(1, Int32(backingBounds.width.rounded(.toNearestOrAwayFromZero)))
        let height = max(1, Int32(backingBounds.height.rounded(.toNearestOrAwayFromZero)))

        openGLContext.makeCurrentContext()
        openGLContext.update()
        _ = renderAPI.update(context: renderContext)

        var fbo = MPVOpenGLFBO(fbo: 0, w: width, h: height, internal_format: 0)
        var flipY: Int32 = 1
        let result = withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flipY) { flipYPointer in
                var params = [
                    MPVRenderParam(
                        type: MPV_RENDER_PARAM_OPENGL_FBO,
                        data: UnsafeMutableRawPointer(fboPointer)
                    ),
                    MPVRenderParam(
                        type: MPV_RENDER_PARAM_FLIP_Y,
                        data: UnsafeMutableRawPointer(flipYPointer)
                    ),
                    MPVRenderParam(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]

                return params.withUnsafeMutableBufferPointer { paramsBuffer in
                    renderAPI.render(
                        context: renderContext,
                        params: UnsafeMutableRawPointer(paramsBuffer.baseAddress)
                    )
                }
            }
        }

        if result < 0, !hasLoggedRenderError {
            hasLoggedRenderError = true
            print("Spike render failed: mpv_render_context_render returned \(result)")
        }

        openGLContext.flushBuffer()
    }

    @MainActor
    func shutdown() {
        markShuttingDown()

        if let renderContext, let renderAPI {
            renderAPI.setUpdateCallback(context: renderContext, callback: nil, callbackContext: nil)
            openGLView?.openGLContext?.makeCurrentContext()
            renderAPI.free(context: renderContext)
        }

        renderContext = nil
        renderAPI = nil

        if let openGLLibrary {
            dlclose(openGLLibrary)
            self.openGLLibrary = nil
        }
    }

    func scheduleRenderFromCallback() {
        guard markRenderScheduledIfNeeded() else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.clearRenderScheduled()
            self.renderNow()
        }
    }

    func lookupOpenGLProcAddress(_ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
        guard let name else {
            recordMissingOpenGLProcName("<null>")
            return nil
        }

        guard let openGLLibrary else {
            recordMissingOpenGLProcName(String(cString: name))
            return nil
        }

        guard let symbol = dlsym(openGLLibrary, name) else {
            recordMissingOpenGLProcName(String(cString: name))
            return nil
        }

        return symbol
    }

    @MainActor
    private func createRenderContext(core: MPVScopedRenderCore) throws -> CreatedRenderContext {
        resetOpenGLProcLookupFailure()

        var context: UnsafeMutableRawPointer?
        var apiType = Array("opengl".utf8CString)
        var initParams = MPVOpenGLInitParams(
            get_proc_address: mpvOpenGLGetProcAddressCallback,
            get_proc_address_ctx: callbackContext,
            extra_exts: nil
        )

        let result = apiType.withUnsafeMutableBufferPointer { apiTypeBuffer in
            withUnsafeMutablePointer(to: &initParams) { initParamsPointer in
                var params = [
                    MPVRenderParam(
                        type: MPV_RENDER_PARAM_API_TYPE,
                        data: UnsafeMutableRawPointer(apiTypeBuffer.baseAddress)
                    ),
                    MPVRenderParam(
                        type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                        data: UnsafeMutableRawPointer(initParamsPointer)
                    ),
                    MPVRenderParam(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]

                return params.withUnsafeMutableBufferPointer { paramsBuffer in
                    core.renderAPI.renderContextCreate(
                        result: &context,
                        handle: core.handle,
                        params: UnsafeMutableRawPointer(paramsBuffer.baseAddress)
                    )
                }
            }
        }

        guard result >= 0 else {
            if let missingOpenGLProcName = readMissingOpenGLProcName() {
                throw PlaybackError.mpvError("OpenGL function lookup failed: \(missingOpenGLProcName)")
            }

            throw MPVMapper.playbackError(
                fromMPVCode: result,
                api: core.api,
                fallback: "mpv render context creation failed"
            )
        }

        guard let context else {
            throw PlaybackError.mpvError("mpv render context creation returned no context")
        }

        return CreatedRenderContext(renderAPI: core.renderAPI, context: context)
    }

    private static func openOpenGLLibrary() throws -> UnsafeMutableRawPointer {
        let candidates = [
            "/System/Library/Frameworks/OpenGL.framework/OpenGL",
            "/System/Library/Frameworks/OpenGL.framework/Versions/Current/OpenGL",
            "/System/Library/Frameworks/OpenGL.framework/Versions/Current/Libraries/libGL.dylib"
        ]

        for candidate in candidates {
            if let library = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) {
                return library
            }
        }

        throw PlaybackError.mpvError("OpenGL function lookup failed: OpenGL framework could not be loaded")
    }

    private var callbackContext: UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }

    private func markRenderScheduledIfNeeded() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !isShuttingDown, !isRenderScheduled else {
            return false
        }

        isRenderScheduled = true
        return true
    }

    private func clearRenderScheduled() {
        lock.lock()
        isRenderScheduled = false
        lock.unlock()
    }

    private func markShuttingDown() {
        lock.lock()
        isShuttingDown = true
        isRenderScheduled = false
        lock.unlock()
    }

    private func readShuttingDown() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return isShuttingDown
    }

    private func resetOpenGLProcLookupFailure() {
        lock.lock()
        missingOpenGLProcName = nil
        lock.unlock()
    }

    private func recordMissingOpenGLProcName(_ name: String) {
        lock.lock()
        if missingOpenGLProcName == nil {
            missingOpenGLProcName = name
        }
        lock.unlock()
    }

    private func readMissingOpenGLProcName() -> String? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return missingOpenGLProcName
    }
}

private struct CreatedRenderContext: @unchecked Sendable {
    let renderAPI: MPVRenderAPI
    let context: UnsafeMutableRawPointer
}

private let mpvOpenGLGetProcAddressCallback: MPVOpenGLGetProcAddress = { callbackContext, name in
    guard let callbackContext else {
        return nil
    }

    let adapter = Unmanaged<MPVOpenGLRenderAdapter>.fromOpaque(callbackContext).takeUnretainedValue()
    return adapter.lookupOpenGLProcAddress(name)
}

private let mpvRenderUpdateCallback: MPVRenderUpdateCallback = { callbackContext in
    guard let callbackContext else {
        return
    }

    let adapter = Unmanaged<MPVOpenGLRenderAdapter>.fromOpaque(callbackContext).takeUnretainedValue()
    adapter.scheduleRenderFromCallback()
}
