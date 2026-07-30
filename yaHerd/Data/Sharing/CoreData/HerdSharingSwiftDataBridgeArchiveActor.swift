import CoreData
import Foundation
import SwiftData

@ModelActor
actor HerdSharingSwiftDataBridgeArchiveActor {
    func makeArchive(for herdPublicID: UUID) throws -> HerdSharingBridgeArchive {
        try PerformanceLog.measure("HerdSharingSwiftDataBridgeArchiveActor.makeArchive") {
            let herdID = herdPublicID
            var herdDescriptor = FetchDescriptor<Herd>(
                predicate: #Predicate<Herd> { herd in
                    herd.publicID == herdID
                }
            )
            herdDescriptor.fetchLimit = 1
            guard let herd = try modelContext.fetch(herdDescriptor).first else {
                throw HerdSharingActionError.shareRootMissing
            }

            let summary = herd.toSummary()
            let mirroredAt = Date.now
            let bridgeModel = HerdSharingCoreDataModelFactory.makeCurrentModel()
            var records: [HerdSharingBridgeRecordSnapshot] = []

            records.append(
                try makeSnapshot(
                    SharedHerdRecord.self,
                    entityName: SharedHerdRecord.entityName,
                    model: bridgeModel
                ) { record in
                    record.mirror(summary, mirroredAt: mirroredAt)
                }
            )

            for definition in try fetchAll(FetchDescriptor<TagColorDefinition>()).filter({
                $0.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedTagColorDefinitionRecord.self, entityName: SharedTagColorDefinitionRecord.entityName, model: bridgeModel) {
                    $0.mirror(definition, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for statusReference in try fetchAll(FetchDescriptor<AnimalStatusReference>()).filter({
                $0.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedAnimalStatusReferenceRecord.self, entityName: SharedAnimalStatusReferenceRecord.entityName, model: bridgeModel) {
                    $0.mirror(statusReference, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for pastureGroup in try fetchAll(FetchDescriptor<PastureGroup>()).filter({
                $0.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedPastureGroupRecord.self, entityName: SharedPastureGroupRecord.entityName, model: bridgeModel) {
                    $0.mirror(pastureGroup, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for pasture in try fetchAll(FetchDescriptor<Pasture>()).filter({
                $0.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedPastureRecord.self, entityName: SharedPastureRecord.entityName, model: bridgeModel) {
                    $0.mirror(pasture, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for animal in try fetchAll(FetchDescriptor<Animal>()).filter({
                $0.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedAnimalRecord.self, entityName: SharedAnimalRecord.entityName, model: bridgeModel) {
                    $0.mirror(animal, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for tag in try fetchAll(FetchDescriptor<AnimalTag>()).filter({
                $0.herd?.publicID == herdID || $0.animal?.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedAnimalTagRecord.self, entityName: SharedAnimalTagRecord.entityName, model: bridgeModel) {
                    $0.mirror(tag, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for movement in try fetchAll(FetchDescriptor<MovementRecord>()).filter({
                $0.herd?.publicID == herdID || $0.animal?.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedMovementRecord.self, entityName: SharedMovementRecord.entityName, model: bridgeModel) {
                    $0.mirror(movement, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for statusRecord in try fetchAll(FetchDescriptor<StatusRecord>()).filter({
                $0.herd?.publicID == herdID || $0.animal?.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedStatusRecord.self, entityName: SharedStatusRecord.entityName, model: bridgeModel) {
                    $0.mirror(statusRecord, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for template in try fetchAll(FetchDescriptor<WorkingProtocolTemplate>()).filter({
                $0.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedWorkingProtocolTemplateRecord.self, entityName: SharedWorkingProtocolTemplateRecord.entityName, model: bridgeModel) {
                    $0.mirror(template, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for session in try fetchAll(FetchDescriptor<WorkingSession>()).filter({
                $0.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedWorkingSessionRecord.self, entityName: SharedWorkingSessionRecord.entityName, model: bridgeModel) {
                    $0.mirror(session, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for queueItem in try fetchAll(FetchDescriptor<WorkingQueueItem>()).filter({
                $0.herd?.publicID == herdID || $0.session?.herd?.publicID == herdID || $0.animal?.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedWorkingQueueItemRecord.self, entityName: SharedWorkingQueueItemRecord.entityName, model: bridgeModel) {
                    $0.mirror(queueItem, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for treatmentRecord in try fetchAll(FetchDescriptor<WorkingTreatmentRecord>()).filter({
                $0.herd?.publicID == herdID || $0.session?.herd?.publicID == herdID || $0.animal?.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedWorkingTreatmentRecord.self, entityName: SharedWorkingTreatmentRecord.entityName, model: bridgeModel) {
                    $0.mirror(treatmentRecord, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for healthRecord in try fetchAll(FetchDescriptor<HealthRecord>()).filter({
                $0.herd?.publicID == herdID || $0.animal?.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedHealthRecord.self, entityName: SharedHealthRecord.entityName, model: bridgeModel) {
                    $0.mirror(healthRecord, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for pregnancyCheck in try fetchAll(FetchDescriptor<PregnancyCheck>()).filter({
                $0.herd?.publicID == herdID || $0.animal?.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedPregnancyCheckRecord.self, entityName: SharedPregnancyCheckRecord.entityName, model: bridgeModel) {
                    $0.mirror(pregnancyCheck, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for session in try fetchAll(FetchDescriptor<FieldCheckSession>()).filter({
                $0.herd?.publicID == herdID || $0.pasture?.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedFieldCheckSessionRecord.self, entityName: SharedFieldCheckSessionRecord.entityName, model: bridgeModel) {
                    $0.mirror(session, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for check in try fetchAll(FetchDescriptor<FieldCheckAnimalCheck>()).filter({
                $0.herd?.publicID == herdID || $0.session?.herd?.publicID == herdID || $0.animal?.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedFieldCheckAnimalCheckRecord.self, entityName: SharedFieldCheckAnimalCheckRecord.entityName, model: bridgeModel) {
                    $0.mirror(check, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            for finding in try fetchAll(FetchDescriptor<FieldCheckFinding>()).filter({
                $0.herd?.publicID == herdID || $0.session?.herd?.publicID == herdID || $0.animal?.herd?.publicID == herdID
            }) {
                records.append(try makeSnapshot(SharedFieldCheckFindingRecord.self, entityName: SharedFieldCheckFindingRecord.entityName, model: bridgeModel) {
                    $0.mirror(finding, herdPublicID: herdID, mirroredAt: mirroredAt)
                })
            }

            return HerdSharingBridgeArchive(
                herd: summary,
                mirroredAt: mirroredAt,
                records: records
            )
        }
    }

    private func makeSnapshot<Record: NSManagedObject>(
        _ type: Record.Type,
        entityName: String,
        model: NSManagedObjectModel,
        configure: (Record) -> Void
    ) throws -> HerdSharingBridgeRecordSnapshot {
        guard let entity = model.entitiesByName[entityName] else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "The Core Data sharing bridge model is missing \(entityName)."
            )
        }
        let record = Record(entity: entity, insertInto: nil)
        configure(record)
        return try HerdSharingBridgeArchiveCodec.snapshot(record)
    }

    private func fetchAll<Model: PersistentModel>(
        _ baseDescriptor: FetchDescriptor<Model>,
        pageSize: Int = 250
    ) throws -> [Model] {
        var offset = 0
        var results: [Model] = []

        while true {
            var descriptor = baseDescriptor
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = pageSize
            let page = try modelContext.fetch(descriptor)
            results.append(contentsOf: page)
            guard page.count == pageSize else { break }
            offset += page.count
        }

        return results
    }
}
