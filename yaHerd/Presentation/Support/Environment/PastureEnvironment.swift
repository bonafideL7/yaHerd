import Foundation
import SwiftUI

enum MissingPastureDependencyError: LocalizedError {
    case pastureListRepository
    case pastureCreateRepository
    case pastureDetailRepository
    case pastureGroupListRepository
    case pastureGroupDetailRepository
    case pastureGroupEditorRepository
    case pastureReferenceDataReader
    case animalPastureMover
    case fieldCheckPastureArchiveWriter

    var errorDescription: String? {
        switch self {
        case .pastureListRepository:
            return "Pasture list repository has not been configured."
        case .pastureCreateRepository:
            return "Pasture create repository has not been configured."
        case .pastureDetailRepository:
            return "Pasture detail repository has not been configured."
        case .pastureGroupListRepository:
            return "Pasture group list repository has not been configured."
        case .pastureGroupDetailRepository:
            return "Pasture group detail repository has not been configured."
        case .pastureGroupEditorRepository:
            return "Pasture group editor repository has not been configured."
        case .pastureReferenceDataReader:
            return "Pasture reference data reader has not been configured."
        case .animalPastureMover:
            return "Animal pasture mover has not been configured."
        case .fieldCheckPastureArchiveWriter:
            return "Field check pasture archive writer has not been configured."
        }
    }
}

private struct MissingPastureListRepository: PastureListRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchPastures() throws -> [PastureSummary] {
        throw MissingPastureDependencyError.pastureListRepository
    }

    func reorder(ids: [UUID]) throws {
        throw MissingPastureDependencyError.pastureListRepository
    }

    func delete(ids: [UUID]) throws {
        throw MissingPastureDependencyError.pastureListRepository
    }

    func validatePastureIDsExist(_ ids: [UUID]) throws {
        throw MissingPastureDependencyError.pastureListRepository
    }

    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        throw MissingPastureDependencyError.pastureListRepository
    }
}

private struct MissingPastureCreateRepository: PastureCreateRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        throw MissingPastureDependencyError.pastureCreateRepository
    }

    func create(input: PastureInput) throws -> PastureDetailSnapshot {
        throw MissingPastureDependencyError.pastureCreateRepository
    }
}

private struct MissingPastureDetailEditingRepository: PastureDetailEditingRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? {
        throw MissingPastureDependencyError.pastureDetailRepository
    }

    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        throw MissingPastureDependencyError.pastureDetailRepository
    }

    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        throw MissingPastureDependencyError.pastureDetailRepository
    }

    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot {
        throw MissingPastureDependencyError.pastureDetailRepository
    }
}

private struct MissingPastureGroupListRepository: PastureGroupListRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchPastureGroups() throws -> [PastureGroupSummary] {
        throw MissingPastureDependencyError.pastureGroupListRepository
    }

    func deleteGroups(ids: [UUID]) throws {
        throw MissingPastureDependencyError.pastureGroupListRepository
    }

    func validatePastureGroupIDsExist(_ ids: [UUID]) throws {
        throw MissingPastureDependencyError.pastureGroupListRepository
    }
}

private struct MissingPastureGroupDetailRepository: PastureGroupDetailRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchPastureGroupDetail(id: UUID) throws -> PastureGroupDetailSnapshot? {
        throw MissingPastureDependencyError.pastureGroupDetailRepository
    }

    func fetchPastures() throws -> [PastureSummary] {
        throw MissingPastureDependencyError.pastureGroupDetailRepository
    }

    func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws {
        throw MissingPastureDependencyError.pastureGroupDetailRepository
    }

    func validatePastureIDsExist(_ ids: [UUID]) throws {
        throw MissingPastureDependencyError.pastureGroupDetailRepository
    }

    func validatePastureGroupIDsExist(_ ids: [UUID]) throws {
        throw MissingPastureDependencyError.pastureGroupDetailRepository
    }
}

private struct MissingPastureGroupEditorRepository: PastureGroupEditorRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    func groupNameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        throw MissingPastureDependencyError.pastureGroupEditorRepository
    }

    func createGroup(input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        throw MissingPastureDependencyError.pastureGroupEditorRepository
    }

    func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        throw MissingPastureDependencyError.pastureGroupEditorRepository
    }
}

private struct MissingPastureReferenceReader: PastureReferenceDataReader {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchPastureOptions() throws -> [PastureOption] {
        throw MissingPastureDependencyError.pastureReferenceDataReader
    }
}

private struct MissingAnimalPastureMover: AnimalPastureMoving {
    nonisolated init(environmentFallback _: Void = ()) {}

    func move(ids: [UUID], toPastureID: UUID?) throws {
        throw MissingPastureDependencyError.animalPastureMover
    }
}

private struct MissingFieldCheckPastureArchiveWriter: FieldCheckPastureArchiveWriter {
    nonisolated init(environmentFallback _: Void = ()) {}

    func archiveSessionsForDeletedPastures(_ ids: [UUID], archivedAt: Date) throws {
        throw MissingPastureDependencyError.fieldCheckPastureArchiveWriter
    }
}

private struct PastureListRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any PastureListRepository = MissingPastureListRepository()
}

private struct PastureCreateRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any PastureCreateRepository = MissingPastureCreateRepository()
}

private struct PastureDetailEditingRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any PastureDetailEditingRepository = MissingPastureDetailEditingRepository()
}

private struct PastureGroupListRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any PastureGroupListRepository = MissingPastureGroupListRepository()
}

private struct PastureGroupDetailRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any PastureGroupDetailRepository = MissingPastureGroupDetailRepository()
}

private struct PastureGroupEditorRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: any PastureGroupEditorRepository = MissingPastureGroupEditorRepository()
}

private struct PastureReferenceReaderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any PastureReferenceDataReader = MissingPastureReferenceReader()
}

private struct AnimalPastureMoverEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AnimalPastureMoving = MissingAnimalPastureMover()
}

private struct FieldCheckPastureArchiveWriterEnvironmentKey: EnvironmentKey {
    static let defaultValue: any FieldCheckPastureArchiveWriter = MissingFieldCheckPastureArchiveWriter()
}

extension EnvironmentValues {
    var pastureListRepository: any PastureListRepository {
        get { self[PastureListRepositoryEnvironmentKey.self] }
        set { self[PastureListRepositoryEnvironmentKey.self] = newValue }
    }

    var pastureCreateRepository: any PastureCreateRepository {
        get { self[PastureCreateRepositoryEnvironmentKey.self] }
        set { self[PastureCreateRepositoryEnvironmentKey.self] = newValue }
    }

    var pastureDetailRepository: any PastureDetailEditingRepository {
        get { self[PastureDetailEditingRepositoryEnvironmentKey.self] }
        set { self[PastureDetailEditingRepositoryEnvironmentKey.self] = newValue }
    }

    var pastureGroupListRepository: any PastureGroupListRepository {
        get { self[PastureGroupListRepositoryEnvironmentKey.self] }
        set { self[PastureGroupListRepositoryEnvironmentKey.self] = newValue }
    }

    var pastureGroupDetailRepository: any PastureGroupDetailRepository {
        get { self[PastureGroupDetailRepositoryEnvironmentKey.self] }
        set { self[PastureGroupDetailRepositoryEnvironmentKey.self] = newValue }
    }

    var pastureGroupEditorRepository: any PastureGroupEditorRepository {
        get { self[PastureGroupEditorRepositoryEnvironmentKey.self] }
        set { self[PastureGroupEditorRepositoryEnvironmentKey.self] = newValue }
    }

    var pastureReferenceReader: any PastureReferenceDataReader {
        get { self[PastureReferenceReaderEnvironmentKey.self] }
        set { self[PastureReferenceReaderEnvironmentKey.self] = newValue }
    }

    var animalPastureMover: any AnimalPastureMoving {
        get { self[AnimalPastureMoverEnvironmentKey.self] }
        set { self[AnimalPastureMoverEnvironmentKey.self] = newValue }
    }

    var fieldCheckPastureArchiveWriter: any FieldCheckPastureArchiveWriter {
        get { self[FieldCheckPastureArchiveWriterEnvironmentKey.self] }
        set { self[FieldCheckPastureArchiveWriterEnvironmentKey.self] = newValue }
    }
}
