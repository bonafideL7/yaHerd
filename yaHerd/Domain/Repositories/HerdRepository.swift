//
//  HerdRepository.swift
//  yaHerd
//

import Foundation

@MainActor
protocol HerdRepository: AnyObject {
    func fetchCurrentHerd() throws -> HerdSummary
    func renameCurrentHerd(to name: String) throws -> HerdSummary
}

enum HerdRepositoryError: LocalizedError, Equatable {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Herd name cannot be empty."
        }
    }
}
