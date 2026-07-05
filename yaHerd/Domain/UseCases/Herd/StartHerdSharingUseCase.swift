//
//  StartHerdSharingUseCase.swift
//  yaHerd
//

@MainActor
struct StartHerdSharingUseCase {
    private let repository: any HerdSharingRepository

    init(repository: any HerdSharingRepository) {
        self.repository = repository
    }

    func execute(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        guard let herd else {
            throw HerdSharingActionError.shareRootMissing
        }

        return try await repository.startSharing(
            herd: herd,
            storageMode: storageMode
        )
    }
}
