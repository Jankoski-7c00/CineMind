import Domain

public protocol MediaOpening: Sendable {
    func open(mediaFileID: MediaFileID) throws -> PlayableFile
}

extension OpenMediaUseCase: @unchecked Sendable {}

extension OpenMediaUseCase: MediaOpening {}
