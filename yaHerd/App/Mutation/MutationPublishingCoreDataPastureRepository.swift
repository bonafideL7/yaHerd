import Foundation

/// Core Data Pasture read/edit boundary without the legacy synchronous delete method.
/// Deletion is a separate awaited transaction through PastureDeletionPerforming.
@MainActor
struct MutationPublishingCoreDataPastureRepository:
    PastureListManagingRepository,
    PastureDetailEditingRepository,
    PastureCreateRepository,
    PastureGroupListRepository,
    PastureGroupDetailRepository,
    PastureGroupEditorRepository,
    PastureReferenceDataReader
{
    let base: CoreDataPastureRepository
    let mutationRecorder: any SuccessfulMutationRecording
    let writePolicy: LocalDataWritePolicy

    func fetchPastures() throws -> [PastureSummary] { try base.fetchPastures() }
    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? {
        try base.fetchPastureDetail(id: id)
    }
    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        try base.fetchResidentAnimals(pastureID: pastureID)
    }
    func fetchPastureOptions() throws -> [PastureOption] { try base.fetchPastureOptions() }
    func validatePastureIDsExist(_ ids: [UUID]) throws { try base.validatePastureIDsExist(ids) }
    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        try base.nameExists(name, excluding: id)
    }
    func fetchPastureGroups() throws -> [PastureGroupSummary] { try base.fetchPastureGroups() }
    func fetchPastureGroupDetail(id: UUID) throws -> PastureGroupDetailSnapshot? {
        try base.fetchPastureGroupDetail(id: id)
    }
    func validatePastureGroupIDsExist(_ ids: [UUID]) throws {
        try base.validatePastureGroupIDsExist(ids)
    }
    func groupNameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        try base.groupNameExists(name, excluding: id)
    }

    func create(input: PastureInput) throws -> PastureDetailSnapshot {
        try writePolicy.validateCanWrite()
        let result = try base.create(input: input)
        mutationRecorder.recordSuccessfulMutation(reason: .pasture)
        return result
    }

    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot {
        try writePolicy.validateCanWrite()
        let result = try base.update(id: id, input: input)
        mutationRecorder.recordSuccessfulMutation(reason: .pasture)
        return result
    }

    func reorder(ids: [UUID]) throws {
        try writePolicy.validateCanWrite()
        try base.reorder(ids: ids)
        mutationRecorder.recordSuccessfulMutation(reason: .pasture)
    }

    func createGroup(input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        try writePolicy.validateCanWrite()
        let result = try base.createGroup(input: input)
        mutationRecorder.recordSuccessfulMutation(reason: .pasture)
        return result
    }

    func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        try writePolicy.validateCanWrite()
        let result = try base.updateGroup(id: id, input: input)
        mutationRecorder.recordSuccessfulMutation(reason: .pasture)
        return result
    }

    func deleteGroups(ids: [UUID]) throws {
        try writePolicy.validateCanWrite()
        try base.deleteGroups(ids: ids)
        mutationRecorder.recordSuccessfulMutation(reason: .pasture)
    }

    func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws {
        try writePolicy.validateCanWrite()
        try base.assignPasture(id: pastureID, toGroupID: groupID)
        mutationRecorder.recordSuccessfulMutation(reason: .pasture)
    }
}
