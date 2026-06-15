import SwiftUI

public struct LibraryCommandActions {
    public let canAddFolder: Bool
    public let canScanLibrary: Bool
    public let canTogglePresentation: Bool

    private let addFolderAction: () -> Void
    private let scanLibraryAction: () -> Void
    private let togglePresentationAction: () -> Void
    private let toggleInspectorAction: () -> Void

    public init(
        canAddFolder: Bool,
        canScanLibrary: Bool,
        canTogglePresentation: Bool,
        addFolder: @escaping () -> Void,
        scanLibrary: @escaping () -> Void,
        togglePresentation: @escaping () -> Void,
        toggleInspector: @escaping () -> Void
    ) {
        self.canAddFolder = canAddFolder
        self.canScanLibrary = canScanLibrary
        self.canTogglePresentation = canTogglePresentation
        self.addFolderAction = addFolder
        self.scanLibraryAction = scanLibrary
        self.togglePresentationAction = togglePresentation
        self.toggleInspectorAction = toggleInspector
    }

    public func addFolder() {
        addFolderAction()
    }

    public func scanLibrary() {
        scanLibraryAction()
    }

    public func togglePresentation() {
        togglePresentationAction()
    }

    public func toggleInspector() {
        toggleInspectorAction()
    }
}

private struct LibraryCommandActionsKey: FocusedValueKey {
    typealias Value = LibraryCommandActions
}

public extension FocusedValues {
    var libraryCommandActions: LibraryCommandActions? {
        get { self[LibraryCommandActionsKey.self] }
        set { self[LibraryCommandActionsKey.self] = newValue }
    }
}
