//
//  RenameCurrentHerdUseCase.swift
//  yaHerd
//

@MainActor
struct RenameCurrentHerdUseCase {
    private let repository: any HerdRepository

    init(repository: any HerdRepository) {
        self.repository = repository
    }

    func execute(name: String) throws -> HerdSummary {
        try repository.renameCurrentHerd(to: name)
    }
}
