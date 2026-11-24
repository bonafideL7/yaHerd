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
    case accountUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Herd name cannot be empty."
        case .missingHerd:
            "No herd exists yet. Add herd data before using herd-specific actions."
        case .incompleteOwnedHerdImport:
            "An existing owned Herd is incomplete. Wait for its import to finish before creating another Herd."
        case .accountUnavailable:
            "iCloud account authorization is unavailable. No Herd changes can be made in this session until access is restored."
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
