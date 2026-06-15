enum LibraryInspectorSection: String, CaseIterable, Identifiable {
    case info
    case organize
    case files
    case subtitles
    case advancedMetadata

    var id: Self { self }

    var title: String {
        switch self {
        case .info:
            "Info"
        case .organize:
            "Organize"
        case .files:
            "Files"
        case .subtitles:
            "Subtitles"
        case .advancedMetadata:
            "Metadata"
        }
    }

    var systemImage: String {
        switch self {
        case .info:
            "info.circle"
        case .organize:
            "star"
        case .files:
            "doc"
        case .subtitles:
            "captions.bubble"
        case .advancedMetadata:
            "slider.horizontal.3"
        }
    }
}
