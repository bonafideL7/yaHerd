import Foundation

enum PastureRepositoryError: LocalizedError, Equatable {
    case duplicatePastureIDs
    case duplicatePastureGroupIDs
    case pastureIDsNotFound([UUID])
    case pastureGroupIDsNotFound([UUID])

    var errorDescription: String? {
        switch self {
        case .duplicatePastureIDs:
            return "Pasture IDs must be unique."
        case .duplicatePastureGroupIDs:
            return "Pasture group IDs must be unique."
        case .pastureIDsNotFound(let ids):
            let identifierList = ids.map(\.uuidString).joined(separator: ", ")
            return "One or more pastures could not be found: \(identifierList)."
        case .pastureGroupIDsNotFound(let ids):
            let identifierList = ids.map(\.uuidString).joined(separator: ", ")
            return "One or more pasture groups could not be found: \(identifierList)."
        }
    }
}

@MainActor
protocol PastureListReader {
    func fetchPastures() throws -> [PastureSummary]
}

@MainActor
protocol PastureDetailReader {
    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot?
}

@MainActor
protocol PastureResidentAnimalReader {
    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary]
}

@MainActor
protocol PastureAssignedAnimalReader {
    func fetchAssignedAnimals(pastureID: UUID) throws -> [AnimalSummary]
}

extension PastureAssignedAnimalReader where Self: PastureResidentAnimalReader {
    func fetchAssignedAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        try fetchResidentAnimals(pastureID: pastureID)
    }
}

@MainActor
protocol PastureExistenceChecking {
    func validatePastureIDsExist(_ ids: [UUID]) throws
}

@MainActor
protocol PastureReferenceDataReader {
    func fetchPastureOptions() throws -> [PastureOption]
}

@MainActor
protocol PastureNameChecking {
    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool
}

@MainActor
protocol PastureCreating {
    @discardableResult
    func create(input: PastureInput) throws -> PastureDetailSnapshot
}

@MainActor
protocol PastureUpdating {
    @discardableResult
    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot
}

@MainActor
protocol PastureOrdering {
    func reorder(ids: [UUID]) throws
}

@MainActor
protocol PastureDeleting {
    func delete(ids: [UUID]) throws
}

@MainActor
protocol PastureGroupListReader {
    func fetchPastureGroups() throws -> [PastureGroupSummary]
}

@MainActor
protocol PastureGroupDetailReader {
    func fetchPastureGroupDetail(id: UUID) throws -> PastureGroupDetailSnapshot?
}

@MainActor
protocol PastureGroupExistenceChecking {
    func validatePastureGroupIDsExist(_ ids: [UUID]) throws
}

@MainActor
protocol PastureGroupNameChecking {
    func groupNameExists(_ name: String, excluding id: UUID?) throws -> Bool
}

@MainActor
protocol PastureGroupCreating {
    @discardableResult
    func createGroup(input: PastureGroupInput) throws -> PastureGroupDetailSnapshot
}

@MainActor
protocol PastureGroupUpdating {
    @discardableResult
    func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot
}

@MainActor
protocol PastureGroupDeleting {
    func deleteGroups(ids: [UUID]) throws
}

@MainActor
protocol PastureGroupAssignmentWriting {
    func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws
}

@MainActor
protocol PastureCreateRepository: PastureNameChecking, PastureCreating {}
@MainActor
protocol PastureUpdateRepository: PastureNameChecking, PastureUpdating {}
@MainActor
protocol PastureGroupCreateRepository: PastureGroupNameChecking, PastureGroupCreating {}
@MainActor
protocol PastureGroupUpdateRepository: PastureGroupNameChecking, PastureGroupUpdating {}
@MainActor
protocol PastureGroupDeleteRepository: PastureGroupDeleting, PastureGroupExistenceChecking {}
@MainActor
protocol PastureGroupAssignRepository: PastureGroupAssignmentWriting, PastureExistenceChecking, PastureGroupExistenceChecking {}
@MainActor
protocol PastureDetailRepository: PastureDetailReader, PastureResidentAnimalReader, PastureAssignedAnimalReader {}
@MainActor
protocol PastureDeleteRepository: PastureDeleting, PastureExistenceChecking, PastureResidentAnimalReader {}

@MainActor
protocol PastureListRepository: PastureListReader, PastureOrdering, PastureDeleteRepository {}
@MainActor
protocol PastureDetailEditingRepository: PastureDetailRepository, PastureUpdateRepository {}
@MainActor
protocol PastureGroupListRepository: PastureGroupListReader, PastureGroupDeleteRepository {}
@MainActor
protocol PastureGroupDetailRepository: PastureGroupDetailReader, PastureListReader, PastureGroupAssignRepository {}
@MainActor
protocol PastureGroupEditorRepository: PastureGroupCreateRepository, PastureGroupUpdateRepository {}

@MainActor
protocol PastureRepository: PastureListRepository,
                            PastureDetailEditingRepository,
                            PastureReferenceDataReader,
                            PastureCreateRepository,
                            PastureGroupListRepository,
                            PastureGroupDetailRepository,
                            PastureGroupEditorRepository {}
