//
//  LoadCurrentHerdUseCase.swift
//  yaHerd
//

@MainActor
struct LoadCurrentHerdUseCase {
    private let repository: any HerdRepository

    init(repository: any HerdRepository) {
        self.repository = repository
    }

    func execute() throws -> HerdSummary {
        try repository.fetchCurrentHerd()
    }
}
