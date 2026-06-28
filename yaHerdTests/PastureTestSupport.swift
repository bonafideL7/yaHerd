import Foundation
@testable import yaHerd

enum PastureTestSupport {
    static func makeSummary(
        id: UUID = UUID(),
        name: String,
        acreage: Double? = nil,
        usableAcreage: Double? = nil,
        targetAcresPerHead: Double? = nil,
        activeAnimalCount: Int = 0,
        sortOrder: Int = 0,
        lastGrazedDate: Date? = nil,
        groupID: UUID? = nil,
        groupName: String? = nil,
        restDays: Int? = nil
    ) -> PastureSummary {
        PastureSummary(
            id: id,
            name: name,
            acreage: acreage,
            usableAcreage: usableAcreage,
            targetAcresPerHead: targetAcresPerHead,
            activeAnimalCount: activeAnimalCount,
            sortOrder: sortOrder,
            lastGrazedDate: lastGrazedDate,
            groupID: groupID,
            groupName: groupName,
            restDays: restDays
        )
    }

    static func makeDetail(
        id: UUID = UUID(),
        name: String,
        acreage: Double? = nil,
        usableAcreage: Double? = nil,
        targetAcresPerHead: Double? = nil,
        activeAnimalCount: Int = 0,
        lastGrazedDate: Date? = nil,
        groupID: UUID? = nil,
        groupName: String? = nil
    ) -> PastureDetailSnapshot {
        PastureDetailSnapshot(
            id: id,
            name: name,
            acreage: acreage,
            usableAcreage: usableAcreage,
            targetAcresPerHead: targetAcresPerHead,
            activeAnimalCount: activeAnimalCount,
            lastGrazedDate: lastGrazedDate,
            groupID: groupID,
            groupName: groupName
        )
    }

    static func makeAnimalSummary(id: UUID = UUID(), displayTagNumber: String = "12") -> AnimalSummary {
        AnimalSummary(
            id: id,
            name: "Cow \(displayTagNumber)",
            displayTagNumber: displayTagNumber,
            displayTagColorID: nil,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            sex: .female,
            animalType: .cow,
            firstDistinguishingFeature: nil,
            birthDate: .distantPast,
            status: .active,
            isArchived: false,
            pastureID: nil,
            pastureName: nil,
            location: .pasture
        )
    }
}

final class PastureCreateRepositorySpy: PastureCreateRepository {
    var duplicateNames: Set<String> = []
    private(set) var receivedExcludingIDs: [UUID?] = []
    private(set) var createdInputs: [PastureInput] = []
    var detailToReturn = PastureTestSupport.makeDetail(name: "North")

    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        receivedExcludingIDs.append(id)
        return duplicateNames.contains(name.lowercased())
    }

    func create(input: PastureInput) throws -> PastureDetailSnapshot {
        createdInputs.append(input)
        return detailToReturn
    }
}

final class PastureUpdateRepositorySpy: PastureUpdateRepository {
    var duplicateNames: Set<String> = []
    private(set) var updatedIDs: [UUID] = []
    private(set) var updatedInputs: [PastureInput] = []
    private(set) var receivedExcludingIDs: [UUID?] = []
    var detailToReturn = PastureTestSupport.makeDetail(name: "North")

    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        receivedExcludingIDs.append(id)
        return duplicateNames.contains(name.lowercased())
    }

    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot {
        updatedIDs.append(id)
        updatedInputs.append(input)
        return detailToReturn
    }
}

final class PastureGroupRepositorySpy: PastureGroupCreateRepository, PastureGroupUpdateRepository {
    var duplicateNames: Set<String> = []
    private(set) var createdInputs: [PastureGroupInput] = []
    private(set) var updatedIDs: [UUID] = []
    private(set) var updatedInputs: [PastureGroupInput] = []
    private(set) var receivedExcludingIDs: [UUID?] = []
    var detailToReturn = PastureGroupDetailSnapshot(id: UUID(), name: "Spring", grazeDays: 7, restDays: 21, pastures: [])

    func groupNameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        receivedExcludingIDs.append(id)
        return duplicateNames.contains(name.lowercased())
    }

    func createGroup(input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        createdInputs.append(input)
        return detailToReturn
    }

    func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        updatedIDs.append(id)
        updatedInputs.append(input)
        return detailToReturn
    }
}

final class PastureOrderingSpy: PastureOrdering {
    private(set) var reorderedIDs: [[UUID]] = []
    var errorToThrow: Error?

    func reorder(ids: [UUID]) throws {
        if let errorToThrow { throw errorToThrow }
        reorderedIDs.append(ids)
    }
}

final class PastureDeleteRepositorySpy: PastureDeleteRepository, PastureOrdering {
    var existingIDs: Set<UUID> = []
    var residentAnimalsByPastureID: [UUID: [AnimalSummary]] = [:]
    private(set) var validateCalls: [[UUID]] = []
    private(set) var fetchedResidentPastureIDs: [UUID] = []
    private(set) var deletedIDs: [[UUID]] = []
    private(set) var reorderedIDs: [[UUID]] = []

    func validatePastureIDsExist(_ ids: [UUID]) throws {
        validateCalls.append(ids)
        let missing = ids.filter { !existingIDs.contains($0) }
        if !missing.isEmpty {
            throw PastureRepositoryError.pastureIDsNotFound(missing)
        }
    }

    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        fetchedResidentPastureIDs.append(pastureID)
        return residentAnimalsByPastureID[pastureID, default: []]
    }

    func delete(ids: [UUID]) throws {
        deletedIDs.append(ids)
    }

    func reorder(ids: [UUID]) throws {
        reorderedIDs.append(ids)
    }
}

final class AnimalPastureMovingSpy: AnimalPastureMoving {
    private(set) var moveCalls: [(ids: [UUID], pastureID: UUID?)] = []

    func move(ids: [UUID], toPastureID: UUID?) throws {
        moveCalls.append((ids, toPastureID))
    }
}

final class FieldCheckPastureCleanupWriterSpy: FieldCheckPastureCleanupWriter {
    private(set) var cleanupCalls: [[UUID]] = []

    func deleteSessions(forPastureIDs pastureIDs: [UUID]) throws {
        cleanupCalls.append(pastureIDs)
    }
}

final class PastureListReaderStub: PastureListReader {
    var result: Result<[PastureSummary], Error>

    init(result: Result<[PastureSummary], Error>) {
        self.result = result
    }

    func fetchPastures() throws -> [PastureSummary] {
        try result.get()
    }
}

enum PastureTestError: LocalizedError, Equatable {
    case forced

    var errorDescription: String? {
        "Forced test error."
    }
}

final class PastureGroupDeleteRepositorySpy: PastureGroupDeleteRepository {
    var existingIDs: Set<UUID> = []
    private(set) var validateCalls: [[UUID]] = []
    private(set) var deletedIDs: [[UUID]] = []

    func validatePastureGroupIDsExist(_ ids: [UUID]) throws {
        validateCalls.append(ids)
        guard Set(ids).count == ids.count else {
            throw PastureRepositoryError.duplicatePastureGroupIDs
        }
        let missing = ids.filter { !existingIDs.contains($0) }
        if !missing.isEmpty {
            throw PastureRepositoryError.pastureGroupIDsNotFound(missing)
        }
    }

    func deleteGroups(ids: [UUID]) throws {
        deletedIDs.append(ids)
    }
}

final class PastureGroupAssignRepositorySpy: PastureGroupAssignRepository {
    var existingPastureIDs: Set<UUID> = []
    var existingGroupIDs: Set<UUID> = []
    private(set) var validatedPastureIDs: [[UUID]] = []
    private(set) var validatedGroupIDs: [[UUID]] = []
    private(set) var assignmentCalls: [(pastureID: UUID, groupID: UUID?)] = []

    func validatePastureIDsExist(_ ids: [UUID]) throws {
        validatedPastureIDs.append(ids)
        let missing = ids.filter { !existingPastureIDs.contains($0) }
        if !missing.isEmpty {
            throw PastureRepositoryError.pastureIDsNotFound(missing)
        }
    }

    func validatePastureGroupIDsExist(_ ids: [UUID]) throws {
        validatedGroupIDs.append(ids)
        let missing = ids.filter { !existingGroupIDs.contains($0) }
        if !missing.isEmpty {
            throw PastureRepositoryError.pastureGroupIDsNotFound(missing)
        }
    }

    func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws {
        assignmentCalls.append((pastureID, groupID))
    }
}
