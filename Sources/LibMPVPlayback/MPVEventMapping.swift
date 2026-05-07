import Darwin
import Foundation
import Playback

let MPV_FORMAT_NONE: Int32 = 0
let MPV_FORMAT_STRING: Int32 = 1
let MPV_FORMAT_FLAG: Int32 = 3
let MPV_FORMAT_INT64: Int32 = 4
let MPV_FORMAT_DOUBLE: Int32 = 5
let MPV_FORMAT_NODE: Int32 = 6
let MPV_FORMAT_NODE_ARRAY: Int32 = 7
let MPV_FORMAT_NODE_MAP: Int32 = 8

let MPV_ERROR_EVENT_QUEUE_FULL: Int32 = -1
let MPV_ERROR_NOMEM: Int32 = -2
let MPV_ERROR_UNINITIALIZED: Int32 = -3
let MPV_ERROR_INVALID_PARAMETER: Int32 = -4
let MPV_ERROR_OPTION_NOT_FOUND: Int32 = -5
let MPV_ERROR_OPTION_FORMAT: Int32 = -6
let MPV_ERROR_OPTION_ERROR: Int32 = -7
let MPV_ERROR_PROPERTY_NOT_FOUND: Int32 = -8
let MPV_ERROR_PROPERTY_FORMAT: Int32 = -9
let MPV_ERROR_PROPERTY_UNAVAILABLE: Int32 = -10
let MPV_ERROR_PROPERTY_ERROR: Int32 = -11
let MPV_ERROR_COMMAND: Int32 = -12
let MPV_ERROR_LOADING_FAILED: Int32 = -13
let MPV_ERROR_AO_INIT_FAILED: Int32 = -14
let MPV_ERROR_VO_INIT_FAILED: Int32 = -15
let MPV_ERROR_NOTHING_TO_PLAY: Int32 = -16
let MPV_ERROR_UNKNOWN_FORMAT: Int32 = -17
let MPV_ERROR_UNSUPPORTED: Int32 = -18
let MPV_ERROR_NOT_IMPLEMENTED: Int32 = -19
let MPV_ERROR_GENERIC: Int32 = -20

let MPV_EVENT_NONE: Int32 = 0
let MPV_EVENT_SHUTDOWN: Int32 = 1
let MPV_EVENT_END_FILE: Int32 = 7
let MPV_EVENT_FILE_LOADED: Int32 = 8
let MPV_EVENT_PROPERTY_CHANGE: Int32 = 22
let MPV_EVENT_QUEUE_OVERFLOW: Int32 = 24

let MPV_END_FILE_REASON_EOF: Int32 = 0
let MPV_END_FILE_REASON_STOP: Int32 = 2
let MPV_END_FILE_REASON_QUIT: Int32 = 3
let MPV_END_FILE_REASON_ERROR: Int32 = 4

struct MPVEvent {
    var event_id: Int32
    var error: Int32
    var reply_userdata: UInt64
    var data: UnsafeMutableRawPointer?
}

struct MPVEventProperty {
    var name: UnsafePointer<CChar>?
    var format: Int32
    var data: UnsafeMutableRawPointer?
}

struct MPVEventEndFile {
    var reason: Int32
    var error: Int32
    var playlist_entry_id: Int64
    var playlist_insert_id: Int64
    var playlist_insert_num_entries: Int32
}

struct MPVNode {
    var u = MPVNodeUnion()
    var format: Int32 = MPV_FORMAT_NONE
}

struct MPVNodeUnion {
    var storage: UInt64 = 0

    var string: UnsafePointer<CChar>? {
        UnsafePointer<CChar>(bitPattern: UInt(storage))
    }

    var flag: Int32 {
        Int32(bitPattern: UInt32(truncatingIfNeeded: storage))
    }

    var int64: Int64 {
        Int64(bitPattern: storage)
    }

    var double_: Double {
        Double(bitPattern: storage)
    }

    var list: UnsafeMutablePointer<MPVNodeList>? {
        UnsafeMutablePointer<MPVNodeList>(bitPattern: UInt(storage))
    }
}

struct MPVNodeList {
    var num: Int32
    var values: UnsafeMutablePointer<MPVNode>?
    var keys: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
}

final class MPVClientAPI {
    private typealias Create = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias Initialize = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias TerminateDestroy = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias SetOptionString = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> Int32
    private typealias RequestLogMessages = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?
    ) -> Int32
    private typealias ObserveProperty = @convention(c) (
        UnsafeMutableRawPointer?,
        UInt64,
        UnsafePointer<CChar>?,
        Int32
    ) -> Int32
    private typealias WaitEvent = @convention(c) (
        UnsafeMutableRawPointer?,
        Double
    ) -> UnsafeMutableRawPointer?
    private typealias GetProperty = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?,
        Int32,
        UnsafeMutableRawPointer?
    ) -> Int32
    private typealias SetProperty = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?,
        Int32,
        UnsafeMutableRawPointer?
    ) -> Int32
    private typealias SetPropertyString = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> Int32
    private typealias Command = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<UnsafePointer<CChar>?>?
    ) -> Int32
    private typealias FreeNodeContents = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias ErrorString = @convention(c) (Int32) -> UnsafePointer<CChar>?

    private let library: UnsafeMutableRawPointer
    private let createFunction: Create
    private let initializeFunction: Initialize
    private let terminateDestroyFunction: TerminateDestroy
    private let setOptionStringFunction: SetOptionString
    private let requestLogMessagesFunction: RequestLogMessages
    private let observePropertyFunction: ObserveProperty
    private let waitEventFunction: WaitEvent
    private let getPropertyFunction: GetProperty
    private let setPropertyFunction: SetProperty
    private let setPropertyStringFunction: SetPropertyString
    private let commandFunction: Command
    private let freeNodeContentsFunction: FreeNodeContents
    private let errorStringFunction: ErrorString

    init() throws {
        let candidates = [
            "libmpv.2.dylib",
            "libmpv.dylib",
            "/opt/homebrew/opt/mpv/lib/libmpv.2.dylib",
            "/opt/homebrew/opt/mpv/lib/libmpv.dylib",
            "/usr/local/opt/mpv/lib/libmpv.2.dylib",
            "/usr/local/opt/mpv/lib/libmpv.dylib"
        ]

        guard let library = candidates.lazy.compactMap({ dlopen($0, RTLD_NOW | RTLD_LOCAL) }).first else {
            throw PlaybackError.mpvUnavailable
        }

        self.library = library
        do {
            createFunction = try Self.symbol("mpv_create", in: library, as: Create.self)
            initializeFunction = try Self.symbol("mpv_initialize", in: library, as: Initialize.self)
            terminateDestroyFunction = try Self.symbol(
                "mpv_terminate_destroy",
                in: library,
                as: TerminateDestroy.self
            )
            setOptionStringFunction = try Self.symbol(
                "mpv_set_option_string",
                in: library,
                as: SetOptionString.self
            )
            requestLogMessagesFunction = try Self.symbol(
                "mpv_request_log_messages",
                in: library,
                as: RequestLogMessages.self
            )
            observePropertyFunction = try Self.symbol(
                "mpv_observe_property",
                in: library,
                as: ObserveProperty.self
            )
            waitEventFunction = try Self.symbol("mpv_wait_event", in: library, as: WaitEvent.self)
            getPropertyFunction = try Self.symbol("mpv_get_property", in: library, as: GetProperty.self)
            setPropertyFunction = try Self.symbol("mpv_set_property", in: library, as: SetProperty.self)
            setPropertyStringFunction = try Self.symbol(
                "mpv_set_property_string",
                in: library,
                as: SetPropertyString.self
            )
            commandFunction = try Self.symbol("mpv_command", in: library, as: Command.self)
            freeNodeContentsFunction = try Self.symbol(
                "mpv_free_node_contents",
                in: library,
                as: FreeNodeContents.self
            )
            errorStringFunction = try Self.symbol("mpv_error_string", in: library, as: ErrorString.self)
        } catch {
            dlclose(library)
            throw error
        }
    }

    deinit {
        dlclose(library)
    }

    func create() -> UnsafeMutableRawPointer? {
        createFunction()
    }

    func initialize(_ handle: UnsafeMutableRawPointer?) -> Int32 {
        initializeFunction(handle)
    }

    func terminateDestroy(_ handle: UnsafeMutableRawPointer?) {
        terminateDestroyFunction(handle)
    }

    func setOptionString(_ handle: UnsafeMutableRawPointer?, _ name: String, _ value: String) -> Int32 {
        name.withCString { namePointer in
            value.withCString { valuePointer in
                setOptionStringFunction(handle, namePointer, valuePointer)
            }
        }
    }

    func requestLogMessages(_ handle: UnsafeMutableRawPointer?, _ level: String) -> Int32 {
        level.withCString { levelPointer in
            requestLogMessagesFunction(handle, levelPointer)
        }
    }

    func observeProperty(
        _ handle: UnsafeMutableRawPointer?,
        _ replyUserdata: UInt64,
        _ name: String,
        _ format: Int32
    ) -> Int32 {
        name.withCString { namePointer in
            observePropertyFunction(handle, replyUserdata, namePointer, format)
        }
    }

    func waitEvent(_ handle: UnsafeMutableRawPointer?, _ timeout: Double) -> UnsafeMutablePointer<MPVEvent>? {
        waitEventFunction(handle, timeout)?.assumingMemoryBound(to: MPVEvent.self)
    }

    func getProperty<T>(
        _ handle: UnsafeMutableRawPointer?,
        _ name: String,
        _ format: Int32,
        _ value: inout T
    ) -> Int32 {
        name.withCString { namePointer in
            withUnsafeMutablePointer(to: &value) { valuePointer in
                getPropertyFunction(handle, namePointer, format, UnsafeMutableRawPointer(valuePointer))
            }
        }
    }

    func setProperty<T>(
        _ handle: UnsafeMutableRawPointer?,
        _ name: String,
        _ format: Int32,
        _ value: inout T
    ) -> Int32 {
        name.withCString { namePointer in
            withUnsafeMutablePointer(to: &value) { valuePointer in
                setPropertyFunction(handle, namePointer, format, UnsafeMutableRawPointer(valuePointer))
            }
        }
    }

    func setPropertyString(_ handle: UnsafeMutableRawPointer?, _ name: String, _ value: String) -> Int32 {
        name.withCString { namePointer in
            value.withCString { valuePointer in
                setPropertyStringFunction(handle, namePointer, valuePointer)
            }
        }
    }

    func command(
        _ handle: UnsafeMutableRawPointer?,
        _ arguments: UnsafePointer<UnsafePointer<CChar>?>?
    ) -> Int32 {
        commandFunction(handle, arguments)
    }

    func freeNodeContents(_ node: UnsafeMutablePointer<MPVNode>?) {
        freeNodeContentsFunction(UnsafeMutableRawPointer(node))
    }

    func errorString(for code: Int32) -> String? {
        guard let message = errorStringFunction(code) else {
            return nil
        }

        return String(cString: message)
    }

    private static func symbol<T>(_ name: String, in library: UnsafeMutableRawPointer, as type: T.Type) throws -> T {
        guard let rawSymbol = dlsym(library, name) else {
            throw PlaybackError.mpvUnavailable
        }

        return unsafeBitCast(rawSymbol, to: type)
    }
}

enum MPVMapper {
    static func milliseconds(fromSeconds seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }

        return Int((seconds * 1_000).rounded())
    }

    static func playbackError(from error: any Error) -> PlaybackError {
        if let playbackError = error as? PlaybackError {
            return playbackError
        }

        return .unknown(String(describing: error))
    }

    static func playbackError(
        fromMPVCode code: Int32,
        api: MPVClientAPI,
        playableFile: PlayableFile? = nil,
        fallback: String
    ) -> PlaybackError {
        switch code {
        case MPV_ERROR_UNKNOWN_FORMAT, MPV_ERROR_NOTHING_TO_PLAY, MPV_ERROR_UNSUPPORTED:
            return .unsupportedFormat
        case MPV_ERROR_LOADING_FAILED:
            if let playableFile {
                var isDirectory: ObjCBool = false
                if !FileManager.default.fileExists(
                    atPath: playableFile.url.path,
                    isDirectory: &isDirectory
                ) || isDirectory.boolValue {
                    return .fileMissing
                }

                if !FileManager.default.isReadableFile(atPath: playableFile.url.path) {
                    return .permissionDenied
                }
            }
            return .unsupportedFormat
        case MPV_ERROR_UNINITIALIZED,
             MPV_ERROR_EVENT_QUEUE_FULL,
             MPV_ERROR_NOMEM,
             MPV_ERROR_INVALID_PARAMETER,
             MPV_ERROR_OPTION_NOT_FOUND,
             MPV_ERROR_OPTION_FORMAT,
             MPV_ERROR_OPTION_ERROR,
             MPV_ERROR_PROPERTY_NOT_FOUND,
             MPV_ERROR_PROPERTY_FORMAT,
             MPV_ERROR_PROPERTY_UNAVAILABLE,
             MPV_ERROR_PROPERTY_ERROR,
             MPV_ERROR_COMMAND,
             MPV_ERROR_AO_INIT_FAILED,
             MPV_ERROR_VO_INIT_FAILED,
             MPV_ERROR_NOT_IMPLEMENTED,
             MPV_ERROR_GENERIC:
            return .mpvError(errorMessage(fromMPVCode: code, api: api, fallback: fallback))
        default:
            return .unknown("mpv error \(code): \(errorMessage(fromMPVCode: code, api: api, fallback: fallback))")
        }
    }

    static func propertyChange(from event: MPVEvent) -> MPVPropertyChange? {
        guard let data = event.data else {
            return nil
        }

        guard let observedProperty = MPVObservedProperty(rawValue: event.reply_userdata) else {
            return nil
        }

        let property = data.assumingMemoryBound(to: MPVEventProperty.self).pointee
        return MPVPropertyChange(
            observedProperty: observedProperty,
            format: property.format,
            data: property.data
        )
    }

    static func tracks(from node: MPVNode) -> (audioTracks: [PlaybackTrack], subtitleTracks: [PlaybackTrack]) {
        var audioTracks: [PlaybackTrack] = []
        var subtitleTracks: [PlaybackTrack] = []

        for trackNode in nodeArray(node) {
            guard let type = stringValue(mapValue(trackNode, key: "type")),
                  let id = stringValue(mapValue(trackNode, key: "id")) else {
                continue
            }

            let trackType: PlaybackTrackType
            switch type {
            case "audio":
                trackType = .audio
            case "sub":
                trackType = .subtitle
            default:
                continue
            }

            let track = PlaybackTrack(
                id: id,
                type: trackType,
                language: stringValue(mapValue(trackNode, key: "lang")),
                title: stringValue(mapValue(trackNode, key: "title")),
                isDefault: boolValue(mapValue(trackNode, key: "default")) ?? false,
                isSelected: boolValue(mapValue(trackNode, key: "selected")) ?? false
            )

            switch trackType {
            case .audio:
                audioTracks.append(track)
            case .subtitle:
                subtitleTracks.append(track)
            }
        }

        return (audioTracks, subtitleTracks)
    }

    private static func errorMessage(fromMPVCode code: Int32, api: MPVClientAPI, fallback: String) -> String {
        guard let text = api.errorString(for: code) else {
            return fallback
        }
        return text.isEmpty ? fallback : text
    }

    private static func nodeArray(_ node: MPVNode) -> [MPVNode] {
        guard node.format == MPV_FORMAT_NODE_ARRAY,
              let list = node.u.list else {
            return []
        }

        let nodeList = list.pointee
        guard nodeList.num > 0,
              let values = nodeList.values else {
            return []
        }

        return (0..<Int(nodeList.num)).map { values[$0] }
    }

    private static func mapValue(_ node: MPVNode, key: String) -> MPVNode? {
        guard node.format == MPV_FORMAT_NODE_MAP,
              let list = node.u.list else {
            return nil
        }

        let nodeList = list.pointee
        guard nodeList.num > 0,
              let values = nodeList.values,
              let keys = nodeList.keys else {
            return nil
        }

        for index in 0..<Int(nodeList.num) {
            guard let keyPointer = keys[index],
                  String(cString: keyPointer) == key else {
                continue
            }
            return values[index]
        }

        return nil
    }

    private static func stringValue(_ node: MPVNode?) -> String? {
        guard let node else {
            return nil
        }

        switch node.format {
        case MPV_FORMAT_STRING:
            guard let value = node.u.string else {
                return nil
            }
            let string = String(cString: value)
            return string.isEmpty ? nil : string
        case MPV_FORMAT_INT64:
            return String(node.u.int64)
        case MPV_FORMAT_DOUBLE:
            return String(node.u.double_)
        default:
            return nil
        }
    }

    private static func boolValue(_ node: MPVNode?) -> Bool? {
        guard let node else {
            return nil
        }

        switch node.format {
        case MPV_FORMAT_FLAG:
            return node.u.flag != 0
        case MPV_FORMAT_INT64:
            return node.u.int64 != 0
        case MPV_FORMAT_STRING:
            guard let value = node.u.string else {
                return nil
            }
            switch String(cString: value) {
            case "yes", "true", "1":
                return true
            case "no", "false", "0":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }
}

struct MPVPropertyChange {
    let observedProperty: MPVObservedProperty
    let format: Int32
    let data: UnsafeMutableRawPointer?

    var hasValue: Bool {
        format != MPV_FORMAT_NONE && data != nil
    }

    var flagValue: Bool? {
        guard format == MPV_FORMAT_FLAG,
              let data else {
            return nil
        }

        return data.assumingMemoryBound(to: Int32.self).pointee != 0
    }

    var doubleValue: Double? {
        guard format == MPV_FORMAT_DOUBLE,
              let data else {
            return nil
        }

        return data.assumingMemoryBound(to: Double.self).pointee
    }
}
