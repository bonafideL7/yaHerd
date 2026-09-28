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
