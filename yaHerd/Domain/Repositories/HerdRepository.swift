//
//  HerdRepository.swift
//  yaHerd
//

import Foundation

@MainActor
protocol CurrentHerdSelectionReading: AnyObject {
    var currentHerdID: UUID? { get }
}

@MainActor
protocol HerdRepository: AnyObject {
    func fetchCurrentHerd() throws -> HerdSummary
    func fetchAccessibleHerds() throws -> [AccessibleHerd]
    func fetchHerdInventory() throws -> HerdInventory
    func createOwnedHerd(named name: String) async throws -> HerdSummary
    func renameCurrentHerd(to name: String) async throws -> HerdSummary
}

enum HerdRepositoryError: LocalizedError, Equatable, Sendable {
    case emptyName
    case missingHerd

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Herd name cannot be empty."
        case .missingHerd:
            "No herd exists yet. Add herd data before using herd-specific actions."
        }
    }
}

/// Other Herd repository implementations without imports have only complete roots.
/// The Core Data adapter overrides this to report partial CloudKit imports.
extension HerdRepository {
    func fetchHerdInventory() throws -> HerdInventory {
        HerdInventory(herds: try fetchAccessibleHerds(), hasIncompleteRoots: false)
    }
}
