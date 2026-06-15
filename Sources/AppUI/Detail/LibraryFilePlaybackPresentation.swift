import Application

enum LibraryFilePlaybackButtonState: Equatable {
    case play
    case resume
    case disabled(String)

    var title: String {
        switch self {
        case .play:
            "Play"
        case .resume:
            "Resume"
        case .disabled(let title):
            title
        }
    }

    var systemImage: String {
        switch self {
        case .play, .resume:
            "play.fill"
        case .disabled:
            "play.slash"
        }
    }

    var isDisabled: Bool {
        if case .disabled = self {
            return true
        }
        return false
    }
}

enum LibraryFilePlaybackPresentation {
    static func primaryFile(
        in files: [LibraryFileSummary],
        playbackStatus: PlaybackApplicationStatus
    ) -> LibraryFileSummary? {
        if let activeMediaFileID = playbackStatus.mediaFileID,
           let activeFile = files.first(where: {
               $0.mediaFileID == activeMediaFileID && $0.isPlayable
           }) {
            return activeFile
        }

        return files.first(where: \.isPlayable)
    }

    static func buttonState(
        for file: LibraryFileSummary,
        playbackStatus: PlaybackApplicationStatus
    ) -> LibraryFilePlaybackButtonState {
        guard playbackStatus.mediaFileID == file.mediaFileID else {
            return .play
        }

        switch playbackStatus.state {
        case .idle, .ended, .failed:
            return .play
        case .paused:
            return .resume
        case .loading, .ready:
            return .disabled("Starting")
        case .playing:
            return .disabled("Playing")
        case .buffering:
            return .disabled("Buffering")
        }
    }
}
