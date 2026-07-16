//
//  SyncRequestingRepositories.swift
//  yaHerd
//

import Foundation

@MainActor
struct SyncRequestingAnimalRepository: AnimalRepository {
  let base: any AnimalRepository
  let scheduler: HerdSharingMutationSyncScheduler
  let writePolicy: HerdCollaborationWritePolicy

  func fetchAnimals() throws -> [AnimalSummary] { try base.fetchAnimals() }
  func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
    try base.fetchAnimalDetail(id: id)
  }
  func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent] { try base.fetchTimeline(id: id) }
  func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] {
    try base.fetchStatusReferenceOptions()
  }
  func fetchParentOptions(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption] {
    try base.fetchParentOptions(excluding: excludedAnimalID)
  }
  func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed? {
    try base.fetchOffspringDraftSeed(forDamID: damID)
  }

  func create(input: AnimalInput) throws -> AnimalDetailSnapshot {
    try writePolicy.validateCanWrite(reason: .animal)
    let result = try base.create(input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
    return result
  }

  func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
    try writePolicy.validateCanWrite(reason: .animal)
    let result = try base.update(id: id, input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
    return result
  }

  func delete(ids: [UUID]) throws {
    try writePolicy.validateCanWrite(reason: .animal)
    try base.delete(ids: ids)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
  }

  func archive(ids: [UUID]) throws {
    try writePolicy.validateCanWrite(reason: .animal)
    try base.archive(ids: ids)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
  }

  func restore(ids: [UUID]) throws {
    try writePolicy.validateCanWrite(reason: .animal)
    try base.restore(ids: ids)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
  }

  func move(ids: [UUID], toPastureID: UUID?) throws {
    try writePolicy.validateCanWrite(reason: .animal)
    try base.move(ids: ids, toPastureID: toPastureID)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
  }

  func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
    try writePolicy.validateCanWrite(reason: .animal)
    let result = try base.addTag(animalID: animalID, input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
    return result
  }

  func updateTag(animalID: UUID, tagID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot
  {
    try writePolicy.validateCanWrite(reason: .animal)
    let result = try base.updateTag(animalID: animalID, tagID: tagID, input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
    return result
  }

  func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
    try writePolicy.validateCanWrite(reason: .animal)
    let result = try base.promoteTag(animalID: animalID, tagID: tagID)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
    return result
  }

  func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
    try writePolicy.validateCanWrite(reason: .animal)
    let result = try base.retireTag(animalID: animalID, tagID: tagID)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
    return result
  }

  func addHealthRecord(animalID: UUID, input: HealthRecordInput) throws -> AnimalDetailSnapshot {
    try writePolicy.validateCanWrite(reason: .animal)
    let result = try base.addHealthRecord(animalID: animalID, input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
    return result
  }

  func addPregnancyCheck(animalID: UUID, input: PregnancyCheckInput) throws -> AnimalDetailSnapshot
  {
    try writePolicy.validateCanWrite(reason: .animal)
    let result = try base.addPregnancyCheck(animalID: animalID, input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
    return result
  }
}

@MainActor
struct SyncRequestingPastureRepository: PastureRepository {
  let base: any PastureRepository
  let scheduler: HerdSharingMutationSyncScheduler
  let writePolicy: HerdCollaborationWritePolicy

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
    try writePolicy.validateCanWrite(reason: .pasture)
    let result = try base.create(input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .pasture)
    return result
  }

  func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot {
    try writePolicy.validateCanWrite(reason: .pasture)
    let result = try base.update(id: id, input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .pasture)
    return result
  }

  func reorder(ids: [UUID]) throws {
    try writePolicy.validateCanWrite(reason: .pasture)
    try base.reorder(ids: ids)
    scheduler.requestSharedDataSyncAfterMutation(reason: .pasture)
  }

  func delete(ids: [UUID]) throws {
    try writePolicy.validateCanWrite(reason: .pasture)
    try base.delete(ids: ids)
    scheduler.requestSharedDataSyncAfterMutation(reason: .pasture)
  }

  func createGroup(input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
    try writePolicy.validateCanWrite(reason: .pasture)
    let result = try base.createGroup(input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .pasture)
    return result
  }

  func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
    try writePolicy.validateCanWrite(reason: .pasture)
    let result = try base.updateGroup(id: id, input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .pasture)
    return result
  }

  func deleteGroups(ids: [UUID]) throws {
    try writePolicy.validateCanWrite(reason: .pasture)
    try base.deleteGroups(ids: ids)
    scheduler.requestSharedDataSyncAfterMutation(reason: .pasture)
  }

  func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws {
    try writePolicy.validateCanWrite(reason: .pasture)
    try base.assignPasture(id: pastureID, toGroupID: groupID)
    scheduler.requestSharedDataSyncAfterMutation(reason: .pasture)
  }
}

@MainActor
struct SyncRequestingDashboardRepository: DashboardRepository {
  let base: any DashboardRepository
  let scheduler: HerdSharingMutationSyncScheduler
  let writePolicy: HerdCollaborationWritePolicy

  func fetchDashboardRecords() throws -> DashboardRecords { try base.fetchDashboardRecords() }
  func fetchDashboardAnimalRecords(kind: DashboardAnimalListKind) throws -> [DashboardAnimalRecord] {
    try base.fetchDashboardAnimalRecords(kind: kind)
  }
  func fetchDashboardPastureRecords() throws -> [DashboardPastureRecord] {
    try base.fetchDashboardPastureRecords()
  }

  func markPastureGrazedToday(id: UUID, on date: Date) throws {
    try writePolicy.validateCanWrite(reason: .dashboard)
    try base.markPastureGrazedToday(id: id, on: date)
    scheduler.requestSharedDataSyncAfterMutation(reason: .dashboard)
  }
}

@MainActor
struct SyncRequestingFieldCheckRepository: FieldCheckRepository {
  let base: any FieldCheckRepository
  let scheduler: HerdSharingMutationSyncScheduler
  let writePolicy: HerdCollaborationWritePolicy

  func archiveSessionsForDeletedPastures(_ ids: [UUID], archivedAt: Date) throws {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.archiveSessionsForDeletedPastures(ids, archivedAt: archivedAt)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }

  func fetchSessions() throws -> [FieldCheckSessionSummary] { try base.fetchSessions() }
  func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] {
    try base.fetchOpenFindings(limit: limit)
  }
  func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot? {
    try base.fetchSessionDetail(id: id)
  }

  func createSession(input: FieldCheckSessionStartInput) throws -> UUID {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    let result = try base.createSession(input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
    return result
  }

  func updateQuickAnimalTypeCounts(sessionID: UUID, counts: [AnimalType: Int]) throws {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: counts)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }

  func updateNotes(sessionID: UUID, notes: String) throws {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.updateNotes(sessionID: sessionID, notes: notes)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }

  func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool) throws {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.setAnimalCheckCounted(
      sessionID: sessionID, animalCheckID: animalCheckID, isCounted: isCounted)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }

  func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) throws {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.setAnimalCheckMissing(
      sessionID: sessionID, animalCheckID: animalCheckID, isMissing: isMissing)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }

  func addTrackedAnimalToSession(sessionID: UUID, animalID: UUID, checkedAt: Date) throws {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.addTrackedAnimalToSession(
      sessionID: sessionID, animalID: animalID, checkedAt: checkedAt)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }

  func addFinding(sessionID: UUID, input: FieldCheckFindingInput) throws {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.addFinding(sessionID: sessionID, input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }

  func updateFinding(sessionID: UUID, findingID: UUID, input: FieldCheckFindingInput) throws {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.updateFinding(sessionID: sessionID, findingID: findingID, input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }

  func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus) throws
  {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: status)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }

  func deleteFinding(sessionID: UUID, findingID: UUID) throws {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.deleteFinding(sessionID: sessionID, findingID: findingID)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }

  func completeSession(id: UUID) throws {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.completeSession(id: id)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }

  func reopenSession(id: UUID) throws {
    try writePolicy.validateCanWrite(reason: .fieldCheck)
    try base.reopenSession(id: id)
    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
  }
}

@MainActor
final class SyncRequestingHerdRepository: HerdRepository {
  private let base: any HerdRepository
  private let scheduler: HerdSharingMutationSyncScheduler
  private let writePolicy: HerdCollaborationWritePolicy

  init(
    base: any HerdRepository,
    scheduler: HerdSharingMutationSyncScheduler,
    writePolicy: HerdCollaborationWritePolicy
  ) {
    self.base = base
    self.scheduler = scheduler
    self.writePolicy = writePolicy
  }

  func fetchCurrentHerd() throws -> HerdSummary { try base.fetchCurrentHerd() }

  func renameCurrentHerd(to name: String) throws -> HerdSummary {
    try writePolicy.validateCanWrite(reason: .herd)
    let result = try base.renameCurrentHerd(to: name)
    scheduler.requestSharedDataSyncAfterMutation(reason: .herd)
    return result
  }
}

@MainActor
final class SyncRequestingTagColorRepository: TagColorRepository {
  private let base: any TagColorRepository
  private let scheduler: HerdSharingMutationSyncScheduler
  private let writePolicy: HerdCollaborationWritePolicy

  init(
    base: any TagColorRepository,
    scheduler: HerdSharingMutationSyncScheduler,
    writePolicy: HerdCollaborationWritePolicy
  ) {
    self.base = base
    self.scheduler = scheduler
    self.writePolicy = writePolicy
  }

  func fetchColors() throws -> [TagColorSnapshot] { try base.fetchColors() }

  func upsert(_ color: TagColorSnapshot) throws {
    try writePolicy.validateCanWrite(reason: .tagColor)
    try base.upsert(color)
    scheduler.requestSharedDataSyncAfterMutation(reason: .tagColor)
  }

  func setDefaultColor(id: UUID) throws {
    try writePolicy.validateCanWrite(reason: .tagColor)
    try base.setDefaultColor(id: id)
    scheduler.requestSharedDataSyncAfterMutation(reason: .tagColor)
  }

  func deleteColors(ids: [UUID]) throws {
    try writePolicy.validateCanWrite(reason: .tagColor)
    try base.deleteColors(ids: ids)
    scheduler.requestSharedDataSyncAfterMutation(reason: .tagColor)
  }

  func reorder(colorIDs: [UUID]) throws {
    try writePolicy.validateCanWrite(reason: .tagColor)
    try base.reorder(colorIDs: colorIDs)
    scheduler.requestSharedDataSyncAfterMutation(reason: .tagColor)
  }

  func restoreDefaultColors() throws {
    try writePolicy.validateCanWrite(reason: .tagColor)
    try base.restoreDefaultColors()
    scheduler.requestSharedDataSyncAfterMutation(reason: .tagColor)
  }
}

@MainActor
struct SyncRequestingWorkingRepository: WorkingRepository {
  let base: any WorkingRepository
  let scheduler: HerdSharingMutationSyncScheduler
  let writePolicy: HerdCollaborationWritePolicy

  func fetchSessions() throws -> [WorkingSessionSummary] { try base.fetchSessions() }
  func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
    try base.fetchSessionDetail(id: id)
  }
  func fetchTemplates() throws -> [WorkingProtocolTemplateSummary] { try base.fetchTemplates() }
  func fetchTemplateDetail(id: UUID) throws -> WorkingProtocolTemplateDetailSnapshot? {
    try base.fetchTemplateDetail(id: id)
  }
  func fetchQueueItemEditor(sessionID: UUID, queueItemID: UUID) throws
    -> WorkingQueueItemEditorSnapshot?
  {
    try base.fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID)
  }

  func createSession(
    date: Date, sourcePastureID: UUID?, protocolName: String, protocolItems: [WorkingProtocolItem]
  ) throws -> UUID {
    try writePolicy.validateCanWrite(reason: .working)
    let result = try base.createSession(
      date: date,
      sourcePastureID: sourcePastureID,
      protocolName: protocolName,
      protocolItems: protocolItems
    )
    scheduler.requestSharedDataSyncAfterMutation(reason: .working)
    return result
  }

  func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws {
    try writePolicy.validateCanWrite(reason: .working)
    try base.collectAnimals(sessionID: sessionID, animalIDs: animalIDs)
    scheduler.requestSharedDataSyncAfterMutation(reason: .working)
  }

  func complete(
    queueItemID: UUID,
    inSessionID sessionID: UUID,
    treatmentEntries: [WorkingTreatmentEntryInput],
    pregnancyCheck: WorkingPregnancyCheckInput?,
    markCastrated: Bool,
    observationNotes: String
  ) throws {
    try writePolicy.validateCanWrite(reason: .working)
    try base.complete(
      queueItemID: queueItemID,
      inSessionID: sessionID,
      treatmentEntries: treatmentEntries,
      pregnancyCheck: pregnancyCheck,
      markCastrated: markCastrated,
      observationNotes: observationNotes
    )
    scheduler.requestSharedDataSyncAfterMutation(reason: .working)
  }

  func saveEdits(
    forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID,
    input: WorkingSessionAnimalEditInput
  ) throws {
    try writePolicy.validateCanWrite(reason: .working)
    try base.saveEdits(forQueueItemID: queueItemID, inSessionID: sessionID, input: input)
    scheduler.requestSharedDataSyncAfterMutation(reason: .working)
  }

  func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws {
    try writePolicy.validateCanWrite(reason: .working)
    try base.deleteWorkData(forQueueItemID: queueItemID, inSessionID: sessionID)
    scheduler.requestSharedDataSyncAfterMutation(reason: .working)
  }

  func deleteSession(id: UUID) throws {
    try writePolicy.validateCanWrite(reason: .working)
    try base.deleteSession(id: id)
    scheduler.requestSharedDataSyncAfterMutation(reason: .working)
  }

  func completeSession(
    id: UUID,
    assignments: [WorkingQueueDestinationAssignment]
  ) throws {
    try writePolicy.validateCanWrite(reason: .working)
    try base.completeSession(id: id, assignments: assignments)
    scheduler.requestSharedDataSyncAfterMutation(reason: .working)
  }

  func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> UUID {
    try writePolicy.validateCanWrite(reason: .working)
    let result = try base.createTemplate(name: name, items: items)
    scheduler.requestSharedDataSyncAfterMutation(reason: .working)
    return result
  }

  func updateTemplate(id: UUID, name: String, items: [WorkingProtocolItem]) throws {
    try writePolicy.validateCanWrite(reason: .working)
    try base.updateTemplate(id: id, name: name, items: items)
    scheduler.requestSharedDataSyncAfterMutation(reason: .working)
  }

  func deleteTemplates(ids: [UUID]) throws {
    try writePolicy.validateCanWrite(reason: .working)
    try base.deleteTemplates(ids: ids)
    scheduler.requestSharedDataSyncAfterMutation(reason: .working)
  }
}

struct SyncRequestingSampleDataSeeder: SampleDataSeeding {
  let base: any SampleDataSeeding
  let scheduler: HerdSharingMutationSyncScheduler
  let writePolicy: HerdCollaborationWritePolicy

  func seedSampleDataIfNeeded() {
    guard writePolicy.canWrite(reason: .sampleData) else { return }
    base.seedSampleDataIfNeeded()
    scheduler.requestSharedDataSyncAfterMutation(reason: .sampleData)
  }

  func seedLargeSampleDataIfNeeded() {
    guard writePolicy.canWrite(reason: .sampleData) else { return }
    base.seedLargeSampleDataIfNeeded()
    scheduler.requestSharedDataSyncAfterMutation(reason: .sampleData)
  }
}
