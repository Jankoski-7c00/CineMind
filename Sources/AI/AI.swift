import Foundation

public enum AIProviderCapability: String, CaseIterable, Sendable, Equatable, Hashable {
    case embeddings
    case chat

    public var displayName: String {
        switch self {
        case .embeddings:
            "Embeddings"
        case .chat:
            "Chat"
        }
    }
}

public struct AIProviderDescriptor: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let capabilities: Set<AIProviderCapability>

    public init(
        id: String,
        displayName: String,
        capabilities: Set<AIProviderCapability>
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
    }
}

public enum AIProviderError: Error, LocalizedError, Sendable, Equatable {
    case disabled
    case notConfigured
    case unavailable
    case unsupportedCapability(AIProviderCapability)
    case timeout
    case rateLimited
    case invalidRequest
    case invalidResponse
    case cancelled
    case requestFailed

    public var errorDescription: String? {
        switch self {
        case .disabled:
            "AI features are disabled."
        case .notConfigured:
            "No AI provider is configured."
        case .unavailable:
            "The AI provider is unavailable."
        case .unsupportedCapability(let capability):
            "The AI provider does not support \(capability.displayName.lowercased())."
        case .timeout:
            "The AI request timed out."
        case .rateLimited:
            "The AI provider is temporarily rate limited."
        case .invalidRequest:
            "The AI request is invalid."
        case .invalidResponse:
            "The AI provider returned an invalid response."
        case .cancelled:
            "The AI request was cancelled."
        case .requestFailed:
            "The AI request failed."
        }
    }
}

public enum AIPublicMediaType: String, Sendable, Equatable, CaseIterable {
    case movie
    case episode

    public var displayName: String {
        switch self {
        case .movie:
            "Movie"
        case .episode:
            "TV Episode"
        }
    }
}

public enum AIPublicMetadataField: String, Sendable, Equatable, Hashable, CaseIterable {
    case originalTitle
    case summary
    case language
    case releaseDate
    case airDate

    fileprivate var displayName: String {
        switch self {
        case .originalTitle:
            "Original Title"
        case .summary:
            "Summary"
        case .language:
            "Language"
        case .releaseDate:
            "Release Date"
        case .airDate:
            "Air Date"
        }
    }
}

public struct AIPrivacyInput: Sendable, Equatable {
    public let title: String
    public let year: Int?
    public let mediaType: AIPublicMediaType
    public let publicMetadata: [AIPublicMetadataField: String]

    public init(
        title: String,
        year: Int? = nil,
        mediaType: AIPublicMediaType,
        publicMetadata: [AIPublicMetadataField: String] = [:]
    ) {
        self.title = title
        self.year = year
        self.mediaType = mediaType
        self.publicMetadata = publicMetadata
    }
}

public struct ApprovedAIText: Sendable, Equatable {
    public let text: String

    fileprivate init(text: String) {
        self.text = text
    }
}

public struct AIPrivacyProjector: Sendable {
    public static let defaultMaximumLength = 4_096

    public let maximumLength: Int

    public init(maximumLength: Int = AIPrivacyProjector.defaultMaximumLength) {
        self.maximumLength = max(maximumLength, 1)
    }

    public func prepare(_ input: AIPrivacyInput) throws -> ApprovedAIText {
        var lines = [
            line(label: "Title", value: input.title),
            input.year.map { "Year: \($0)" },
            "Media Type: \(input.mediaType.displayName)"
        ].compactMap { $0 }

        for field in AIPublicMetadataField.allCases {
            if let value = input.publicMetadata[field],
               let preparedLine = line(label: field.displayName, value: value) {
                lines.append(preparedLine)
            }
        }

        let preparedText = lines.joined(separator: "\n")
        guard !preparedText.isEmpty else {
            throw AIProviderError.invalidRequest
        }

        return ApprovedAIText(text: String(preparedText.prefix(maximumLength)))
    }

    private func line(label: String, value: String) -> String? {
        let normalized = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty, !containsUnsafeContent(normalized) else {
            return nil
        }
        return "\(label): \(normalized)"
    }

    private func containsUnsafeContent(_ value: String) -> Bool {
        let lowercaseValue = value.lowercased()
        let unsafeMarkers = [
            "file://", "smb://", "afp://", "nfs://", "~/", "\\\\"
        ]
        if unsafeMarkers.contains(where: lowercaseValue.contains) {
            return true
        }

        return value
            .components(separatedBy: .whitespacesAndNewlines)
            .map { token in
                token.trimmingCharacters(
                    in: CharacterSet.alphanumerics
                        .union(CharacterSet(charactersIn: "/\\:._~-"))
                        .inverted
                )
            }
            .contains { token in
                isAbsolutePathToken(token) || isHashToken(token)
            }
    }

    private func isAbsolutePathToken(_ token: String) -> Bool {
        if token.hasPrefix("/") && token.dropFirst().contains("/") {
            return true
        }

        let characters = Array(token)
        return characters.count >= 3
            && characters[1] == ":"
            && (characters[2] == "/" || characters[2] == "\\")
    }

    private func isHashToken(_ token: String) -> Bool {
        guard token.count >= 32 else {
            return false
        }
        return token.allSatisfy { $0.isHexDigit }
    }
}

public struct EmbeddingVector: Sendable, Equatable {
    public let values: [Float]

    public init(values: [Float]) throws {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else {
            throw AIProviderError.invalidResponse
        }
        self.values = values
    }
}

public struct EmbeddingRequest: Sendable, Equatable {
    public let input: ApprovedAIText

    public init(input: ApprovedAIText) {
        self.input = input
    }
}

public struct EmbeddingResponse: Sendable, Equatable {
    public let vector: EmbeddingVector

    public init(vector: EmbeddingVector) {
        self.vector = vector
    }
}

public struct ChatRequest: Sendable, Equatable {
    public let input: ApprovedAIText

    public init(input: ApprovedAIText) {
        self.input = input
    }
}

public struct ChatResponse: Sendable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public protocol EmbeddingProvider: Sendable {
    var descriptor: AIProviderDescriptor { get }
    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResponse
}

public protocol ChatProvider: Sendable {
    var descriptor: AIProviderDescriptor { get }
    func complete(_ request: ChatRequest) async throws -> ChatResponse
}

public enum AIProviderUnavailabilityReason: Sendable, Equatable {
    case disabled
    case notConfigured
    case unavailable

    fileprivate var providerError: AIProviderError {
        switch self {
        case .disabled:
            .disabled
        case .notConfigured:
            .notConfigured
        case .unavailable:
            .unavailable
        }
    }
}

public struct UnavailableAIProvider: EmbeddingProvider, ChatProvider {
    public let descriptor: AIProviderDescriptor
    public let reason: AIProviderUnavailabilityReason

    public init(
        descriptor: AIProviderDescriptor,
        reason: AIProviderUnavailabilityReason
    ) {
        self.descriptor = descriptor
        self.reason = reason
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResponse {
        _ = request
        throw reason.providerError
    }

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        _ = request
        throw reason.providerError
    }
}
