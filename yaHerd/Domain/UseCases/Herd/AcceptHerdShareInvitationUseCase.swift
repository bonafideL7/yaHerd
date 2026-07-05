//
//  AcceptHerdShareInvitationUseCase.swift
//  yaHerd
//

@MainActor
struct AcceptHerdShareInvitationUseCase {
    private let repository: any HerdSharingRepository

    init(repository: any HerdSharingRepository) {
        self.repository = repository
    }

    func execute(storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try await repository.acceptPendingShareInvitation(storageMode: storageMode)
    }
}
