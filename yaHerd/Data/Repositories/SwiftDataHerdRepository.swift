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

        // Renaming is an explicit mutation. It may create the first Herd for a genuinely
        // new local workspace, unlike read paths which must never synthesize CloudKit rows.
        let herd = try DefaultHerdBootstrapper.defaultHerd(in: context)
        herd.rename(to: trimmedName)
        try PersistenceLog.save(context, operation: "SwiftDataHerdRepository")
        return herd.toSummary()
    }
}
