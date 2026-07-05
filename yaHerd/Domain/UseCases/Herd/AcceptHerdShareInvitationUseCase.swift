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

    func execute(
        invitation: HerdShareInvitationSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        guard let invitation else {
            throw HerdSharingActionError.shareInvitationMissing
        }

        return try await repository.acceptShareInvitation(
            invitation,
            storageMode: storageMode
        )
    }
}
