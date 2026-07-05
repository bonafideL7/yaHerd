//
//  SwiftDataHerdRepository.swift
//  yaHerd
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataHerdRepository: HerdRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchCurrentHerd() throws -> HerdSummary {
        try currentHerd().toSummary()
    }

    func renameCurrentHerd(to name: String) throws -> HerdSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw HerdRepositoryError.emptyName
        }

        let herd = try currentHerd()
        herd.rename(to: trimmedName)
        try context.save()
        return herd.toSummary()
    }

    private func currentHerd() throws -> Herd {
        try DefaultHerdBootstrapper.defaultHerd(in: context)
    }
}
