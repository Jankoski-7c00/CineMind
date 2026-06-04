import Domain
import Foundation
import Persistence

public struct LibraryTagSummary: Identifiable, Sendable, Equatable {
    public let id: TagID
    public let name: String
    public let sourceLabel: String
    public let mediaItemCountLabel: String?

    public init(
        id: TagID,
        name: String,
        sourceLabel: String,
        mediaItemCountLabel: String?
    ) {
        self.id = id
        self.name = name
        self.sourceLabel = sourceLabel
        self.mediaItemCountLabel = mediaItemCountLabel
    }
}

public struct LibraryCollectionSummary: Identifiable, Sendable, Equatable {
    public let id: CollectionID
    public let name: String
    public let description: String?
    public let mediaItemCountLabel: String?

    public init(
        id: CollectionID,
        name: String,
        description: String?,
        mediaItemCountLabel: String?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.mediaItemCountLabel = mediaItemCountLabel
    }
}

public struct LibraryItemCurationDetail: Sendable, Equatable {
    public let isFavorite: Bool
    public let tags: [LibraryTagSummary]
    public let collections: [LibraryCollectionSummary]

    public init(
        isFavorite: Bool = false,
        tags: [LibraryTagSummary] = [],
        collections: [LibraryCollectionSummary] = []
    ) {
        self.isFavorite = isFavorite
        self.tags = tags
        self.collections = collections
    }
}

public struct LibraryCurationSnapshot: Sendable, Equatable {
    public let tags: [LibraryTagSummary]
    public let collections: [LibraryCollectionSummary]

    public init(
        tags: [LibraryTagSummary] = [],
        collections: [LibraryCollectionSummary] = []
    ) {
        self.tags = tags
        self.collections = collections
    }

    public static let empty = LibraryCurationSnapshot()
}

public enum LibraryCurationError: Error, Sendable, Equatable, LocalizedError {
    case emptyTagName
    case emptyCollectionName
    case duplicateTagName(String)
    case duplicateCollectionName(String)
    case mediaItemNotFound(MediaItemID)
    case tagNotFound(TagID)
    case collectionNotFound(CollectionID)
    case operationFailed(String)

    public var errorDescription: String? {
        message
    }

    public var message: String {
        switch self {
        case .emptyTagName:
            "Tag name cannot be empty."
        case .emptyCollectionName:
            "Collection name cannot be empty."
        case .duplicateTagName(let name):
            "A tag named \"\(name)\" already exists."
        case .duplicateCollectionName(let name):
            "A collection named \"\(name)\" already exists."
        case .mediaItemNotFound:
            "The media item is no longer available."
        case .tagNotFound:
            "The tag is no longer available."
        case .collectionNotFound:
            "The collection is no longer available."
        case .operationFailed(let message):
            message
        }
    }
}

public protocol LibraryCurationBrowsing: Sendable {
    func fetchCurationSnapshot() async throws -> LibraryCurationSnapshot
    func fetchItemCuration(mediaItemID: MediaItemID) async throws -> LibraryItemCurationDetail
}

public protocol LibraryCurationHandling: Sendable {
    func createTag(name: String) async throws -> LibraryTagSummary
    func renameTag(tagID: TagID, name: String) async throws -> LibraryTagSummary
    func deleteTag(tagID: TagID) async throws
    func assignTag(tagID: TagID, mediaItemID: MediaItemID) async throws -> LibraryItemCurationDetail
    func removeTag(tagID: TagID, mediaItemID: MediaItemID) async throws -> LibraryItemCurationDetail

    func setFavorite(mediaItemID: MediaItemID, isFavorite: Bool) async throws -> LibraryItemCurationDetail

    func createCollection(name: String, description: String?) async throws -> LibraryCollectionSummary
    func renameCollection(
        collectionID: CollectionID,
        name: String,
        description: String?
    ) async throws -> LibraryCollectionSummary
    func deleteCollection(collectionID: CollectionID) async throws
    func addToCollection(
        collectionID: CollectionID,
        mediaItemID: MediaItemID
    ) async throws -> LibraryItemCurationDetail
    func removeFromCollection(
        collectionID: CollectionID,
        mediaItemID: MediaItemID
    ) async throws -> LibraryItemCurationDetail
}

public protocol ApplicationLibraryCurationStore: Sendable {
    func fetchMediaItem(id: MediaItemID) throws -> MediaItem?

    func fetchTags() throws -> [PersistedTag]
    func fetchTag(id: TagID) throws -> PersistedTag?
    func fetchTag(normalizedName: String) throws -> PersistedTag?
    func saveTag(_ tag: Tag) throws
    func deleteTag(id: TagID) throws
    func assignTag(tagID: TagID, to mediaItemID: MediaItemID, assignedAt: Date) throws
    func removeTag(tagID: TagID, from mediaItemID: MediaItemID) throws

    func setFavorite(mediaItemID: MediaItemID, isFavorite: Bool, updatedAt: Date) throws
    func fetchMediaItemCuration(mediaItemID: MediaItemID) throws -> PersistedMediaItemCuration

    func fetchCollections() throws -> [PersistedCollection]
    func fetchCollection(id: CollectionID) throws -> PersistedCollection?
    func fetchCollection(normalizedName: String) throws -> PersistedCollection?
    func saveCollection(_ collection: MediaCollection) throws
    func deleteCollection(id: CollectionID) throws
    func addMediaItem(_ mediaItemID: MediaItemID, toCollection collectionID: CollectionID, addedAt: Date) throws
    func removeMediaItem(_ mediaItemID: MediaItemID, fromCollection collectionID: CollectionID) throws
}

extension CineMindStore: ApplicationLibraryCurationStore {}

public struct LibraryCurationUseCase: LibraryCurationBrowsing, LibraryCurationHandling, Sendable {
    private let store: any ApplicationLibraryCurationStore
    private let queue: DispatchQueue
    private let now: @Sendable () -> Date

    public init(
        store: any ApplicationLibraryCurationStore,
        queueLabel: String = "CineMind.LibraryCurationUseCase",
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.queue = DispatchQueue(label: queueLabel)
        self.now = now
    }

    public func fetchCurationSnapshot() async throws -> LibraryCurationSnapshot {
        try await perform {
            LibraryCurationSnapshot(
                tags: try store.fetchTags().map(mapTag),
                collections: try store.fetchCollections().map(mapCollection)
            )
        }
    }

    public func fetchItemCuration(
        mediaItemID: MediaItemID
    ) async throws -> LibraryItemCurationDetail {
        try await perform {
            try ensureMediaItemExists(mediaItemID)
            return try mapItemCuration(store.fetchMediaItemCuration(mediaItemID: mediaItemID))
        }
    }

    public func createTag(name: String) async throws -> LibraryTagSummary {
        try await perform {
            let tag = try makeTag(name: name)
            try ensureUniqueTagName(tag.normalizedName, displayName: tag.name, excludingID: nil)
            try store.saveTag(tag)
            guard let saved = try store.fetchTag(id: tag.id) else {
                throw LibraryCurationError.operationFailed("Tag could not be saved.")
            }
            return mapTag(saved)
        }
    }

    public func renameTag(tagID: TagID, name: String) async throws -> LibraryTagSummary {
        try await perform {
            guard let existing = try store.fetchTag(id: tagID) else {
                throw LibraryCurationError.tagNotFound(tagID)
            }
            let tag = try makeTag(
                id: existing.id,
                name: name,
                source: existing.source,
                createdAt: existing.createdAt
            )
            try ensureUniqueTagName(tag.normalizedName, displayName: tag.name, excludingID: tagID)
            try store.saveTag(tag)
            guard let saved = try store.fetchTag(id: tagID) else {
                throw LibraryCurationError.operationFailed("Tag could not be renamed.")
            }
            return mapTag(saved)
        }
    }

    public func deleteTag(tagID: TagID) async throws {
        try await perform {
            guard try store.fetchTag(id: tagID) != nil else {
                return
            }
            try store.deleteTag(id: tagID)
        }
    }

    public func assignTag(
        tagID: TagID,
        mediaItemID: MediaItemID
    ) async throws -> LibraryItemCurationDetail {
        try await perform {
            try ensureMediaItemExists(mediaItemID)
            try ensureTagExists(tagID)
            try store.assignTag(tagID: tagID, to: mediaItemID, assignedAt: now())
            return try mapItemCuration(store.fetchMediaItemCuration(mediaItemID: mediaItemID))
        }
    }

    public func removeTag(
        tagID: TagID,
        mediaItemID: MediaItemID
    ) async throws -> LibraryItemCurationDetail {
        try await perform {
            try ensureMediaItemExists(mediaItemID)
            try store.removeTag(tagID: tagID, from: mediaItemID)
            return try mapItemCuration(store.fetchMediaItemCuration(mediaItemID: mediaItemID))
        }
    }

    public func setFavorite(
        mediaItemID: MediaItemID,
        isFavorite: Bool
    ) async throws -> LibraryItemCurationDetail {
        try await perform {
            try ensureMediaItemExists(mediaItemID)
            try store.setFavorite(mediaItemID: mediaItemID, isFavorite: isFavorite, updatedAt: now())
            return try mapItemCuration(store.fetchMediaItemCuration(mediaItemID: mediaItemID))
        }
    }

    public func createCollection(
        name: String,
        description: String?
    ) async throws -> LibraryCollectionSummary {
        try await perform {
            let collection = try makeCollection(name: name, description: description)
            try ensureUniqueCollectionName(
                collection.normalizedName,
                displayName: collection.name,
                excludingID: nil
            )
            try store.saveCollection(collection)
            guard let saved = try store.fetchCollection(id: collection.id) else {
                throw LibraryCurationError.operationFailed("Collection could not be saved.")
            }
            return mapCollection(saved)
        }
    }

    public func renameCollection(
        collectionID: CollectionID,
        name: String,
        description: String?
    ) async throws -> LibraryCollectionSummary {
        try await perform {
            guard let existing = try store.fetchCollection(id: collectionID) else {
                throw LibraryCurationError.collectionNotFound(collectionID)
            }
            let collection = try makeCollection(
                id: existing.id,
                name: name,
                description: description,
                createdAt: existing.createdAt
            )
            try ensureUniqueCollectionName(
                collection.normalizedName,
                displayName: collection.name,
                excludingID: collectionID
            )
            try store.saveCollection(collection)
            guard let saved = try store.fetchCollection(id: collectionID) else {
                throw LibraryCurationError.operationFailed("Collection could not be renamed.")
            }
            return mapCollection(saved)
        }
    }

    public func deleteCollection(collectionID: CollectionID) async throws {
        try await perform {
            guard try store.fetchCollection(id: collectionID) != nil else {
                return
            }
            try store.deleteCollection(id: collectionID)
        }
    }

    public func addToCollection(
        collectionID: CollectionID,
        mediaItemID: MediaItemID
    ) async throws -> LibraryItemCurationDetail {
        try await perform {
            try ensureMediaItemExists(mediaItemID)
            try ensureCollectionExists(collectionID)
            try store.addMediaItem(mediaItemID, toCollection: collectionID, addedAt: now())
            return try mapItemCuration(store.fetchMediaItemCuration(mediaItemID: mediaItemID))
        }
    }

    public func removeFromCollection(
        collectionID: CollectionID,
        mediaItemID: MediaItemID
    ) async throws -> LibraryItemCurationDetail {
        try await perform {
            try ensureMediaItemExists(mediaItemID)
            try store.removeMediaItem(mediaItemID, fromCollection: collectionID)
            return try mapItemCuration(store.fetchMediaItemCuration(mediaItemID: mediaItemID))
        }
    }

    private func perform<T>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: mapCurationError(error))
                }
            }
        }
    }

    private func ensureMediaItemExists(_ mediaItemID: MediaItemID) throws {
        guard try store.fetchMediaItem(id: mediaItemID) != nil else {
            throw LibraryCurationError.mediaItemNotFound(mediaItemID)
        }
    }

    private func ensureTagExists(_ tagID: TagID) throws {
        guard try store.fetchTag(id: tagID) != nil else {
            throw LibraryCurationError.tagNotFound(tagID)
        }
    }

    private func ensureCollectionExists(_ collectionID: CollectionID) throws {
        guard try store.fetchCollection(id: collectionID) != nil else {
            throw LibraryCurationError.collectionNotFound(collectionID)
        }
    }

    private func ensureUniqueTagName(
        _ normalizedName: String,
        displayName: String,
        excludingID: TagID?
    ) throws {
        if let existing = try store.fetchTag(normalizedName: normalizedName),
           existing.id != excludingID {
            throw LibraryCurationError.duplicateTagName(displayName)
        }
    }

    private func ensureUniqueCollectionName(
        _ normalizedName: String,
        displayName: String,
        excludingID: CollectionID?
    ) throws {
        if let existing = try store.fetchCollection(normalizedName: normalizedName),
           existing.id != excludingID {
            throw LibraryCurationError.duplicateCollectionName(displayName)
        }
    }

    private func makeTag(
        id: TagID = DomainID.new(),
        name: String,
        source: TagSource = .manual,
        createdAt: Date? = nil
    ) throws -> Tag {
        do {
            let timestamp = now()
            return try Tag.validated(
                id: id,
                name: name,
                source: source,
                createdAt: createdAt ?? timestamp,
                updatedAt: timestamp
            )
        } catch DomainValidationError.emptyTagName {
            throw LibraryCurationError.emptyTagName
        } catch DomainValidationError.emptyNormalizedTagName {
            throw LibraryCurationError.emptyTagName
        }
    }

    private func makeCollection(
        id: CollectionID = DomainID.new(),
        name: String,
        description: String?,
        createdAt: Date? = nil
    ) throws -> MediaCollection {
        do {
            let timestamp = now()
            return try MediaCollection.validated(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt ?? timestamp,
                updatedAt: timestamp
            )
        } catch DomainValidationError.emptyCollectionName {
            throw LibraryCurationError.emptyCollectionName
        } catch DomainValidationError.emptyNormalizedCollectionName {
            throw LibraryCurationError.emptyCollectionName
        }
    }
}

func mapItemCuration(
    _ persisted: PersistedMediaItemCuration
) -> LibraryItemCurationDetail {
    LibraryItemCurationDetail(
        isFavorite: persisted.isFavorite,
        tags: persisted.tags.map(mapTag),
        collections: persisted.collections.map(mapCollection)
    )
}

func mapTag(_ tag: PersistedTag) -> LibraryTagSummary {
    LibraryTagSummary(
        id: tag.id,
        name: tag.name,
        sourceLabel: sourceLabel(tag.source),
        mediaItemCountLabel: countLabel(tag.mediaItemCount)
    )
}

func mapCollection(_ collection: PersistedCollection) -> LibraryCollectionSummary {
    LibraryCollectionSummary(
        id: collection.id,
        name: collection.name,
        description: collection.description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        mediaItemCountLabel: countLabel(collection.mediaItemCount)
    )
}

private func sourceLabel(_ source: TagSource) -> String {
    switch source {
    case .manual:
        "Manual"
    case .aiSuggested:
        "AI"
    case .imported:
        "Imported"
    }
}

private func countLabel(_ count: Int?) -> String? {
    guard let count else {
        return nil
    }
    return count == 1 ? "1 item" : "\(count) items"
}

private func mapCurationError(_ error: Error) -> Error {
    if error is LibraryCurationError {
        return error
    }
    return LibraryCurationError.operationFailed(error.localizedDescription)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
