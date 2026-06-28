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

protocol PastureListReader {
    func fetchPastures() throws -> [PastureSummary]
}

protocol PastureDetailReader {
    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot?
}

protocol PastureResidentAnimalReader {
    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary]
}

protocol PastureExistenceChecking {
    func validatePastureIDsExist(_ ids: [UUID]) throws
}

protocol PastureReferenceDataReader {
    func fetchPastureOptions() throws -> [PastureOption]
}

protocol PastureNameChecking {
    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool
}

protocol PastureCreating {
    @discardableResult
    func create(input: PastureInput) throws -> PastureDetailSnapshot
}

protocol PastureUpdating {
    @discardableResult
    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot
}

protocol PastureOrdering {
    func reorder(ids: [UUID]) throws
}

protocol PastureDeleting {
    func delete(ids: [UUID]) throws
}

protocol PastureGroupListReader {
    func fetchPastureGroups() throws -> [PastureGroupSummary]
}

protocol PastureGroupDetailReader {
    func fetchPastureGroupDetail(id: UUID) throws -> PastureGroupDetailSnapshot?
}

protocol PastureGroupExistenceChecking {
    func validatePastureGroupIDsExist(_ ids: [UUID]) throws
}

protocol PastureGroupNameChecking {
    func groupNameExists(_ name: String, excluding id: UUID?) throws -> Bool
}

protocol PastureGroupCreating {
    @discardableResult
    func createGroup(input: PastureGroupInput) throws -> PastureGroupDetailSnapshot
}

protocol PastureGroupUpdating {
    @discardableResult
    func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot
}

protocol PastureGroupDeleting {
    func deleteGroups(ids: [UUID]) throws
}

protocol PastureGroupAssignmentWriting {
    func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws
}

protocol PastureCreateRepository: PastureNameChecking, PastureCreating {}
protocol PastureUpdateRepository: PastureNameChecking, PastureUpdating {}
protocol PastureGroupCreateRepository: PastureGroupNameChecking, PastureGroupCreating {}
protocol PastureGroupUpdateRepository: PastureGroupNameChecking, PastureGroupUpdating {}
protocol PastureGroupDeleteRepository: PastureGroupDeleting, PastureGroupExistenceChecking {}
protocol PastureGroupAssignRepository: PastureGroupAssignmentWriting, PastureExistenceChecking, PastureGroupExistenceChecking {}
protocol PastureDetailRepository: PastureDetailReader, PastureResidentAnimalReader {}
protocol PastureDeleteRepository: PastureDeleting, PastureExistenceChecking, PastureResidentAnimalReader {}

protocol PastureRepository: PastureListReader,
                            PastureDetailRepository,
                            PastureReferenceDataReader,
                            PastureCreateRepository,
                            PastureUpdateRepository,
                            PastureOrdering,
                            PastureDeleteRepository,
                            PastureGroupListReader,
                            PastureGroupDetailReader,
                            PastureGroupCreateRepository,
                            PastureGroupUpdateRepository,
                            PastureGroupDeleteRepository,
                            PastureGroupAssignRepository {}
