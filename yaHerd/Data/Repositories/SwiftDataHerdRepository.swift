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
        guard let herd = try DefaultHerdBootstrapper.existingDefaultHerd(in: context) else {
            throw HerdRepositoryError.missingHerd
        }
        return herd.toSummary()
    }

    func renameCurrentHerd(to name: String) throws -> HerdSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw HerdRepositoryError.emptyName
        }

        // Renaming is an explicit mutation and may establish the local herd root if needed.
        let herd = try DefaultHerdBootstrapper.defaultHerd(in: context)
        herd.rename(to: trimmedName)
        try PersistenceLog.save(context, operation: "SwiftDataHerdRepository")
        return herd.toSummary()
    }
}
