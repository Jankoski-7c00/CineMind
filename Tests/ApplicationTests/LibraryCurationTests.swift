import Application
import Domain
@testable import Persistence
import XCTest

final class LibraryCurationTests: XCTestCase {
    func testCurationUseCaseMutatesAndMapsItemCuration() async throws {
        let store = try CineMindStore.inMemory()
        let item = MediaItem(id: "item-1", mediaType: .movie, title: "Arrival")
        try store.saveMediaItem(item)

        let useCase = LibraryCurationUseCase(
            store: store,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let tag = try await useCase.createTag(name: "  Sci   Fi  ")
        XCTAssertEqual(tag.name, "Sci Fi")
        XCTAssertEqual(tag.sourceLabel, "Manual")
        XCTAssertEqual(tag.mediaItemCountLabel, "0 items")

        let renamedTag = try await useCase.renameTag(tagID: tag.id, name: "Space Opera")
        XCTAssertEqual(renamedTag.name, "Space Opera")

        let collection = try await useCase.createCollection(
            name: " Weekend Watchlist ",
            description: " Friday "
        )
        XCTAssertEqual(collection.name, "Weekend Watchlist")
        XCTAssertEqual(collection.description, "Friday")

        let renamedCollection = try await useCase.renameCollection(
            collectionID: collection.id,
            name: "Friday Night",
            description: nil
        )
        XCTAssertEqual(renamedCollection.name, "Friday Night")
        XCTAssertNil(renamedCollection.description)

        var curation = try await useCase.assignTag(tagID: tag.id, mediaItemID: item.id)
        XCTAssertEqual(curation.tags.map(\.name), ["Space Opera"])

        curation = try await useCase.setFavorite(mediaItemID: item.id, isFavorite: true)
        XCTAssertTrue(curation.isFavorite)

        curation = try await useCase.addToCollection(
            collectionID: collection.id,
            mediaItemID: item.id
        )
        XCTAssertEqual(curation.collections.map(\.name), ["Friday Night"])

        let snapshot = try await useCase.fetchCurationSnapshot()
        XCTAssertEqual(snapshot.tags.map(\.mediaItemCountLabel), ["1 item"])
        XCTAssertEqual(snapshot.collections.map(\.mediaItemCountLabel), ["1 item"])

        curation = try await useCase.removeTag(tagID: tag.id, mediaItemID: item.id)
        XCTAssertEqual(curation.tags, [])

        curation = try await useCase.removeFromCollection(
            collectionID: collection.id,
            mediaItemID: item.id
        )
        XCTAssertEqual(curation.collections, [])

        try await useCase.deleteTag(tagID: tag.id)
        try await useCase.deleteCollection(collectionID: collection.id)
        let emptySnapshot = try await useCase.fetchCurationSnapshot()
        XCTAssertEqual(emptySnapshot, .empty)
    }

    func testCurationUseCaseReturnsUserSafeValidationErrors() async throws {
        let store = try CineMindStore.inMemory()
        let item = MediaItem(id: "item-1", mediaType: .movie, title: "Arrival")
        try store.saveMediaItem(item)
        let useCase = LibraryCurationUseCase(store: store)

        await assertCurationError(.emptyTagName) {
            _ = try await useCase.createTag(name: "   ")
        }
        await assertCurationError(.emptyCollectionName) {
            _ = try await useCase.createCollection(name: "\n", description: nil)
        }

        let tag = try await useCase.createTag(name: "Sci Fi")
        await assertCurationError(.duplicateTagName("sci fi")) {
            _ = try await useCase.createTag(name: "  sci   fi  ")
        }
        await assertCurationError(.mediaItemNotFound("missing")) {
            _ = try await useCase.assignTag(tagID: tag.id, mediaItemID: "missing")
        }
        await assertCurationError(.tagNotFound("missing-tag")) {
            _ = try await useCase.assignTag(tagID: "missing-tag", mediaItemID: item.id)
        }

        let collection = try await useCase.createCollection(name: "Watchlist", description: nil)
        await assertCurationError(.duplicateCollectionName("watchlist")) {
            _ = try await useCase.createCollection(name: "watchlist", description: nil)
        }
        await assertCurationError(.collectionNotFound("missing-collection")) {
            _ = try await useCase.addToCollection(
                collectionID: "missing-collection",
                mediaItemID: item.id
            )
        }

        try await useCase.deleteCollection(collectionID: collection.id)
    }

    private func assertCurationError(
        _ expected: LibraryCurationError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected).", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LibraryCurationError, expected, file: file, line: line)
        }
    }
}
