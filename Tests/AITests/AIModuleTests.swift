@testable import AI
import XCTest

final class AIModuleTests: XCTestCase {
    func testTargetImportsAndProviderCapabilitiesRemainNarrow() {
        let descriptor = AIProviderDescriptor(
            id: "fake",
            displayName: "Fake Provider",
            capabilities: [.embeddings, .chat]
        )

        XCTAssertEqual(AIProviderCapability.allCases, [.embeddings, .chat])
        XCTAssertEqual(descriptor.capabilities, [.embeddings, .chat])
        XCTAssertEqual(descriptor, descriptor)
    }

    func testEmbeddingVectorRejectsEmptyAndNonFiniteValues() throws {
        XCTAssertThrowsError(try EmbeddingVector(values: [])) { error in
            XCTAssertEqual(error as? AIProviderError, .invalidResponse)
        }
        XCTAssertThrowsError(try EmbeddingVector(values: [.infinity])) { error in
            XCTAssertEqual(error as? AIProviderError, .invalidResponse)
        }

        XCTAssertEqual(
            try EmbeddingVector(values: [0.25, -0.5]).values,
            [0.25, -0.5]
        )
    }

    func testPrivacyProjectionIsDeterministicAndOmitsEmptyFields() throws {
        let input = AIPrivacyInput(
            title: "  Arrival \n",
            year: 2016,
            mediaType: .movie,
            publicMetadata: [
                .summary: " A linguist  meets visitors. ",
                .originalTitle: " ",
                .language: " en "
            ]
        )
        let projector = AIPrivacyProjector()

        let first = try projector.prepare(input)
        let second = try projector.prepare(input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.text,
            """
            Title: Arrival
            Year: 2016
            Media Type: Movie
            Summary: A linguist meets visitors.
            Language: en
            """
        )
    }

    func testPrivacyInputStructurallyExposesOnlyAllowlistedFields() {
        let input = AIPrivacyInput(title: "Arrival", mediaType: .movie)
        let labels = Set(Mirror(reflecting: input).children.compactMap(\.label))
        let forbiddenFragments = [
            "path", "file", "hash", "bookmark", "video", "poster", "subtitle",
            "prompt", "response", "note"
        ]

        XCTAssertEqual(labels, ["title", "year", "mediaType", "publicMetadata"])
        for label in labels {
            XCTAssertFalse(
                forbiddenFragments.contains { label.lowercased().contains($0) }
            )
        }
    }

    func testPrivacyProjectionExcludesRawPathsAndFileHashesFromAllowedFields() throws {
        let rawPath = "/Users/example/Movies/Arrival.mkv"
        let fileHash = String(repeating: "a", count: 64)
        let prepared = try AIPrivacyProjector().prepare(
            AIPrivacyInput(
                title: "Arrival",
                mediaType: .movie,
                publicMetadata: [
                    .summary: "Stored at \(rawPath)",
                    .language: fileHash
                ]
            )
        )

        XCTAssertEqual(
            prepared.text,
            """
            Title: Arrival
            Media Type: Movie
            """
        )
        XCTAssertFalse(prepared.text.contains(rawPath))
        XCTAssertFalse(prepared.text.contains(fileHash))
    }

    func testPrivacyProjectionEnforcesLengthLimitDeterministically() throws {
        let projector = AIPrivacyProjector(maximumLength: 32)
        let input = AIPrivacyInput(
            title: String(repeating: "Arrival ", count: 20),
            mediaType: .movie
        )

        let first = try projector.prepare(input)
        let second = try projector.prepare(input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.text.count, 32)
    }

    func testUnavailableProviderReturnsFocusedErrors() async throws {
        let input = try AIPrivacyProjector().prepare(
            AIPrivacyInput(title: "Arrival", mediaType: .movie)
        )
        let descriptor = AIProviderDescriptor(
            id: "unavailable",
            displayName: "Unavailable Provider",
            capabilities: [.embeddings, .chat]
        )

        for expectedError in [AIProviderError.disabled, .notConfigured, .unavailable] {
            let reason: AIProviderUnavailabilityReason = switch expectedError {
            case .disabled:
                .disabled
            case .notConfigured:
                .notConfigured
            default:
                .unavailable
            }
            let provider = UnavailableAIProvider(descriptor: descriptor, reason: reason)

            do {
                _ = try await provider.embed(EmbeddingRequest(input: input))
                XCTFail("Expected embedding request to fail.")
            } catch {
                XCTAssertEqual(error as? AIProviderError, expectedError)
            }

            do {
                _ = try await provider.complete(ChatRequest(input: input))
                XCTFail("Expected chat request to fail.")
            } catch {
                XCTAssertEqual(error as? AIProviderError, expectedError)
            }
        }
    }

    func testProviderErrorDescriptionsDoNotExposeRequestContent() {
        let privateRequestContent = "/Users/example/private/movie.mkv secret-prompt"
        let errors: [AIProviderError] = [
            .disabled,
            .notConfigured,
            .unavailable,
            .unsupportedCapability(.chat),
            .timeout,
            .rateLimited,
            .invalidRequest,
            .invalidResponse,
            .cancelled,
            .requestFailed
        ]

        for error in errors {
            XCTAssertFalse(error.localizedDescription.contains(privateRequestContent))
            XCTAssertFalse(error.localizedDescription.contains("/Users/example"))
            XCTAssertFalse(error.localizedDescription.contains("secret-prompt"))
        }
    }
}
