import AppKit
import Foundation

@MainActor
final class PlaybackKeyboardShortcutMonitor: ObservableObject {
    private var monitor: Any?
    private var togglePlayPauseAction: (() -> Void)?
    private var seekRelativeAction: ((Int) -> Void)?

    func install(
        togglePlayPause: @escaping () -> Void,
        seekRelative: @escaping (Int) -> Void
    ) {
        togglePlayPauseAction = togglePlayPause
        seekRelativeAction = seekRelative

        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard hasOnlyIgnoredModifiers(event.modifierFlags) else {
            return event
        }

        guard !focusedResponderShouldHandle(event) else {
            return event
        }

        switch event.keyCode {
        case 49:
            guard !event.isARepeat else {
                return nil
            }
            togglePlayPauseAction?()
            return nil
        case 123:
            seekRelativeAction?(-10_000)
            return nil
        case 124:
            seekRelativeAction?(10_000)
            return nil
        default:
            return event
        }
    }

    private func hasOnlyIgnoredModifiers(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        let effectiveModifiers = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        return effectiveModifiers.isEmpty
    }

    private func focusedResponderShouldHandle(_ event: NSEvent) -> Bool {
        guard let firstResponder = event.window?.firstResponder else {
            return false
        }

        // SwiftUI text fields use the window field editor, an NSTextView, as first responder.
        // Let text editing keep normal Space/arrow behavior; playback owns these keys elsewhere.
        if firstResponder is NSTextView {
            return true
        }

        return false
    }
}
