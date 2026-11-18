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
    func createOwnedHerd(named name: String) async throws -> HerdSummary
    func renameCurrentHerd(to name: String) async throws -> HerdSummary
}

enum HerdRepositoryError: LocalizedError, Equatable, Sendable {
    case emptyName
    case missingHerd
    case incompleteOwnedHerd

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Herd name cannot be empty."
        case .missingHerd:
            "No herd exists yet. Add herd data before using herd-specific actions."
        case .incompleteOwnedHerd:
            "An existing owned Herd is incomplete or still importing. Wait for its records to arrive or resolve the incomplete Herd before creating another."
        }
    }
}
