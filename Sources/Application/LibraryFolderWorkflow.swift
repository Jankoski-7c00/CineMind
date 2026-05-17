import Domain
import Foundation
import Persistence

public struct PickedLibraryFolder: Sendable, Equatable {
    public let rootPath: String
    public let displayName: String?
    public let accessBookmark: Data?

    public init(
        rootPath: String,
        displayName: String?,
        accessBookmark: Data?
    ) {
        self.rootPath = rootPath
        self.displayName = displayName
        self.accessBookmark = accessBookmark
    }
}

public protocol LibraryFolderPicking: Sendable {
    @MainActor func pickLibraryFolder() async throws -> PickedLibraryFolder?
}

public struct AddLibraryFolderRequest: Sendable, Equatable {
    public let rootPath: String
    public let displayName: String?
    public let accessBookmark: Data?

    public init(
        rootPath: String,
        displayName: String?,
        accessBookmark: Data?
    ) {
        self.rootPath = rootPath
        self.displayName = displayName
        self.accessBookmark = accessBookmark
    }
}

public struct AddedLibraryFolder: Sendable, Equatable, Identifiable {
    public let id: LibraryFolderID
    public let displayName: String
    public let rootPath: String

    public init(
        id: LibraryFolderID,
        displayName: String,
        rootPath: String
    ) {
        self.id = id
        self.displayName = displayName
        self.rootPath = rootPath
    }
}

public protocol LibraryFolderAdding: Sendable {
    func addFolder(_ request: AddLibraryFolderRequest) async throws -> AddedLibraryFolder
}

public enum LibraryFolderWorkflowError: Error, Sendable, Equatable, LocalizedError {
    case invalidFolderPath
    case folderUnavailable(String)
    case duplicateFolder(String)
    case libraryUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidFolderPath:
            "Choose a valid folder path."
        case .folderUnavailable(let path):
            "The folder is unavailable: \(path)"
        case .duplicateFolder(let path):
            "This folder is already in the library: \(path)"
        case .libraryUnavailable:
            "The library could not be loaded."
        }
    }
}

public protocol ApplicationLibraryFolderMutationStore: Sendable {
    func fetchLibrary() throws -> Library?
    func ensureLibrary(name: String) throws -> Library
    func fetchLibraryFolders(libraryID: LibraryID) throws -> [LibraryFolder]
    func addLibraryFolder(_ folder: LibraryFolder) throws
}

extension CineMindStore: ApplicationLibraryFolderMutationStore {}

public struct AddLibraryFolderUseCase: LibraryFolderAdding, Sendable {
    private static let defaultLibraryName = "CineMind Library"

    private let store: any ApplicationLibraryFolderMutationStore
    private let queue: DispatchQueue

    public init(
        store: any ApplicationLibraryFolderMutationStore,
        queueLabel: String = "CineMind.AddLibraryFolderUseCase"
    ) {
        self.store = store
        self.queue = DispatchQueue(label: queueLabel)
    }

    public func addFolder(_ request: AddLibraryFolderRequest) async throws -> AddedLibraryFolder {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let folder = try Self.addFolder(request, store: store)
                    continuation.resume(returning: folder)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func addFolder(
        _ request: AddLibraryFolderRequest,
        store: any ApplicationLibraryFolderMutationStore
    ) throws -> AddedLibraryFolder {
        let standardizedRootPath = try standardizeRootPath(request.rootPath)
        try validateDirectory(at: standardizedRootPath)

        let library = try currentLibrary(from: store)
        let existingFolders = try fetchFolders(libraryID: library.id, from: store)
        guard !existingFolders.contains(where: { standardizeExistingRootPath($0.rootPath) == standardizedRootPath }) else {
            throw LibraryFolderWorkflowError.duplicateFolder(standardizedRootPath)
        }

        let displayName = resolvedDisplayName(
            requestDisplayName: request.displayName,
            rootPath: standardizedRootPath
        )
        let folder = LibraryFolder(
            libraryID: library.id,
            displayName: displayName,
            rootPath: standardizedRootPath,
            accessBookmark: request.accessBookmark
        )
        try store.addLibraryFolder(folder)

        return AddedLibraryFolder(
            id: folder.id,
            displayName: folder.displayName,
            rootPath: folder.rootPath
        )
    }

    private static func standardizeRootPath(_ rootPath: String) throws -> String {
        let trimmedPath = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              (trimmedPath as NSString).isAbsolutePath else {
            throw LibraryFolderWorkflowError.invalidFolderPath
        }

        let standardizedPath = URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
        guard !standardizedPath.isEmpty,
              (standardizedPath as NSString).isAbsolutePath else {
            throw LibraryFolderWorkflowError.invalidFolderPath
        }

        return standardizedPath
    }

    private static func standardizeExistingRootPath(_ rootPath: String) -> String {
        URL(fileURLWithPath: rootPath).standardizedFileURL.path
    }

    private static func validateDirectory(at path: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LibraryFolderWorkflowError.folderUnavailable(path)
        }
    }

    private static func currentLibrary(
        from store: any ApplicationLibraryFolderMutationStore
    ) throws -> Library {
        do {
            if let library = try store.fetchLibrary() {
                return library
            }

            return try store.ensureLibrary(name: defaultLibraryName)
        } catch {
            throw LibraryFolderWorkflowError.libraryUnavailable
        }
    }

    private static func fetchFolders(
        libraryID: LibraryID,
        from store: any ApplicationLibraryFolderMutationStore
    ) throws -> [LibraryFolder] {
        do {
            return try store.fetchLibraryFolders(libraryID: libraryID)
        } catch {
            throw LibraryFolderWorkflowError.libraryUnavailable
        }
    }

    private static func resolvedDisplayName(
        requestDisplayName: String?,
        rootPath: String
    ) -> String {
        let trimmedDisplayName = requestDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedDisplayName, !trimmedDisplayName.isEmpty {
            return trimmedDisplayName
        }

        return URL(fileURLWithPath: rootPath).lastPathComponent
    }
}
