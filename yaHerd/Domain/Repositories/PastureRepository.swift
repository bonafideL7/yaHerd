import Foundation

enum PastureRepositoryError: LocalizedError, Equatable {
    case duplicatePastureIDs
    case pastureIDsNotFound([UUID])

    var errorDescription: String? {
        switch self {
        case .duplicatePastureIDs:
            return "Pasture IDs must be unique."
        case .pastureIDsNotFound(let ids):
            let identifierList = ids.map(\.uuidString).joined(separator: ", ")
            return "One or more pastures could not be found: \(identifierList)."
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

protocol PastureGroupNameChecking {
    func groupNameExists(_ name: String) throws -> Bool
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

protocol PastureGroupCreating {
    func createGroup(input: PastureGroupInput) throws
}

protocol PastureCreateRepository: PastureNameChecking, PastureCreating {}
protocol PastureUpdateRepository: PastureNameChecking, PastureUpdating {}
protocol PastureGroupCreateRepository: PastureGroupNameChecking, PastureGroupCreating {}
protocol PastureDetailRepository: PastureDetailReader, PastureResidentAnimalReader {}
protocol PastureDeleteRepository: PastureDeleting, PastureExistenceChecking, PastureResidentAnimalReader {}

protocol PastureRepository: PastureListReader,
                            PastureDetailRepository,
                            PastureReferenceDataReader,
                            PastureCreateRepository,
                            PastureUpdateRepository,
                            PastureOrdering,
                            PastureDeleteRepository,
                            PastureGroupCreateRepository {}

struct PastureGroupInput: Hashable {
    var name: String
    var grazeDays: Int
    var restDays: Int

    var normalized: PastureGroupInput {
        PastureGroupInput(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            grazeDays: grazeDays,
            restDays: restDays
        )
    }
}
