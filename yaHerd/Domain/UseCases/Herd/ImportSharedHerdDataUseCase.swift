//
//  ImportSharedHerdDataUseCase.swift
//  yaHerd
//

@MainActor
struct ImportSharedHerdDataUseCase {
    private let repository: any HerdSharingRepository

    init(repository: any HerdSharingRepository) {
        self.repository = repository
    }

    func execute(storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try await repository.importSharedBridgeData(storageMode: storageMode)
    }
}
