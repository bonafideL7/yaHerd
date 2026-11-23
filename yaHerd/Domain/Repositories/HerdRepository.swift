//
//  HerdRepository.swift
//  yaHerd
//

import Foundation

@MainActor
protocol CurrentHerdSelectionReading: AnyObject {
    var currentHerdID: UUID? { get }
    var selectionRevision: UInt64 { get }
}

// Static test selections have no incarnation changes. The application
// selection overrides this with its monotonically increasing revision.
extension CurrentHerdSelectionReading {
    var selectionRevision: UInt64 { 0 }
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
    case incompleteOwnedHerdImport

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Herd name cannot be empty."
        case .missingHerd:
            "No herd exists yet. Add herd data before using herd-specific actions."
        case .incompleteOwnedHerdImport:
            "An existing owned Herd is missing required data. To avoid creating a duplicate, wait for iCloud import to finish or resolve the incomplete record before creating another Herd."
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
