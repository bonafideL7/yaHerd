//
//  LoadHerdSharingReadinessUseCase.swift
//  yaHerd
//

@MainActor
struct LoadHerdSharingReadinessUseCase {
    private let repository: any HerdSharingRepository

    init(repository: any HerdSharingRepository) {
        self.repository = repository
    }

    func execute(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) -> HerdSharingReadiness {
        repository.fetchSharingReadiness(
            for: herd,
            storageMode: storageMode
        )
    }
}
