import Foundation
import SwiftUI

enum MissingFieldCheckDependencyError: LocalizedError {
    case fieldCheckSessionSetupRepository
    case fieldCheckSessionDetailRepository
    case fieldCheckAnimalDetailRepository

    var errorDescription: String? {
        switch self {
        case .fieldCheckSessionSetupRepository:
            return "Field check session setup repository has not been configured."
        case .fieldCheckSessionDetailRepository:
            return "Field check session detail repository has not been configured."
        case .fieldCheckAnimalDetailRepository:
            return "Field check animal detail repository has not been configured."
        }
    }
}

private struct MissingFieldCheckSessionSetupRepository: FieldCheckSessionSetupRepository {
    func createSession(input: FieldCheckSessionStartInput) throws -> UUID {
        throw MissingFieldCheckDependencyError.fieldCheckSessionSetupRepository
    }
}

private struct MissingFieldCheckSessionDetailRepository: FieldCheckSessionDetailRepository {
    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot? {
        throw MissingFieldCheckDependencyError.fieldCheckSessionDetailRepository
    }

    func updateQuickAnimalTypeCounts(sessionID: UUID, counts: [AnimalType: Int]) throws {
        throw MissingFieldCheckDependencyError.fieldCheckSessionDetailRepository
    }

    func updateNotes(sessionID: UUID, notes: String) throws {
        throw MissingFieldCheckDependencyError.fieldCheckSessionDetailRepository
    }

    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool) throws {
        throw MissingFieldCheckDependencyError.fieldCheckSessionDetailRepository
    }

    func setAnimalCheckNeedsAttention(sessionID: UUID, animalCheckID: UUID, needsAttention: Bool) throws {
        throw MissingFieldCheckDependencyError.fieldCheckSessionDetailRepository
    }

    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) throws {
        throw MissingFieldCheckDependencyError.fieldCheckSessionDetailRepository
    }

    func addFinding(sessionID: UUID, input: FieldCheckFindingInput) throws {
        throw MissingFieldCheckDependencyError.fieldCheckSessionDetailRepository
    }

    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus) throws {
        throw MissingFieldCheckDependencyError.fieldCheckSessionDetailRepository
    }

    func deleteFinding(sessionID: UUID, findingID: UUID) throws {
        throw MissingFieldCheckDependencyError.fieldCheckSessionDetailRepository
    }

    func completeSession(id: UUID) throws {
        throw MissingFieldCheckDependencyError.fieldCheckSessionDetailRepository
    }

    func reopenSession(id: UUID) throws {
        throw MissingFieldCheckDependencyError.fieldCheckSessionDetailRepository
    }
}

private struct MissingFieldCheckAnimalDetailRepository: FieldCheckAnimalDetailRepository {
    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot? {
        throw MissingFieldCheckDependencyError.fieldCheckAnimalDetailRepository
    }

    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool) throws {
        throw MissingFieldCheckDependencyError.fieldCheckAnimalDetailRepository
    }

    func setAnimalCheckNeedsAttention(sessionID: UUID, animalCheckID: UUID, needsAttention: Bool) throws {
        throw MissingFieldCheckDependencyError.fieldCheckAnimalDetailRepository
    }

    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) throws {
        throw MissingFieldCheckDependencyError.fieldCheckAnimalDetailRepository
    }

    func addFinding(sessionID: UUID, input: FieldCheckFindingInput) throws {
        throw MissingFieldCheckDependencyError.fieldCheckAnimalDetailRepository
    }

    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus) throws {
        throw MissingFieldCheckDependencyError.fieldCheckAnimalDetailRepository
    }

    func deleteFinding(sessionID: UUID, findingID: UUID) throws {
        throw MissingFieldCheckDependencyError.fieldCheckAnimalDetailRepository
    }
}

private struct FieldCheckSessionSetupRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any FieldCheckSessionSetupRepository = MissingFieldCheckSessionSetupRepository()
}

private struct FieldCheckSessionDetailRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any FieldCheckSessionDetailRepository = MissingFieldCheckSessionDetailRepository()
}

private struct FieldCheckAnimalDetailRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any FieldCheckAnimalDetailRepository = MissingFieldCheckAnimalDetailRepository()
}

extension EnvironmentValues {
    var fieldCheckSessionSetupRepository: any FieldCheckSessionSetupRepository {
        get { self[FieldCheckSessionSetupRepositoryEnvironmentKey.self] }
        set { self[FieldCheckSessionSetupRepositoryEnvironmentKey.self] = newValue }
    }

    var fieldCheckSessionDetailRepository: any FieldCheckSessionDetailRepository {
        get { self[FieldCheckSessionDetailRepositoryEnvironmentKey.self] }
        set { self[FieldCheckSessionDetailRepositoryEnvironmentKey.self] = newValue }
    }

    var fieldCheckAnimalDetailRepository: any FieldCheckAnimalDetailRepository {
        get { self[FieldCheckAnimalDetailRepositoryEnvironmentKey.self] }
        set { self[FieldCheckAnimalDetailRepositoryEnvironmentKey.self] = newValue }
    }
}
