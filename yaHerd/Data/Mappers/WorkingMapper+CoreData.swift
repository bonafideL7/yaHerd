@preconcurrency import CoreData
import Foundation

enum CoreDataWorkingMappingError: Error, Equatable {
    case invalidSessionStatus(sessionID: UUID, value: String?)
    case invalidQueueStatus(queueItemID: UUID, value: String?)
    case missingQueueAnimalID(queueItemID: UUID)
    case invalidAnimalSex(queueItemID: UUID, value: String)
    case invalidPregnancyResult(checkID: UUID, value: String)
    case invalidDoseUnit(recordID: UUID, value: String)
    case invalidAdministrationRoute(recordID: UUID, value: String)
    case corruptPlannedTreatments(sessionID: UUID)
    case corruptTreatmentTemplate(templateID: UUID)
    case corruptTreatmentRecord(recordID: UUID)
    case missingTreatmentDate(recordID: UUID)
    case missingSessionDate(sessionID: UUID)
}

private struct CoreDataWorkingTreatmentPlanItemPayload: Decodable {
    let id: UUID
    let name: String
    let suggestedDose: WorkingTreatmentDose

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case suggestedDose
        case defaultQuantity
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Core Data is authoritative persistence, so a stored plan item must already
        // have stable application identity. Do not use WorkingTreatmentPlanItem's
        // legacy UUID-generating fallback while reading persisted target data.
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""

        if let dose = try container.decodeIfPresent(
            WorkingTreatmentDose.self,
            forKey: .suggestedDose
        ) {
            suggestedDose = dose
        } else {
            let legacyQuantity = try container.decodeIfPresent(
                Double.self,
                forKey: .defaultQuantity
            )
            suggestedDose = WorkingTreatmentDose(amount: legacyQuantity)
        }
    }

    var domainValue: WorkingTreatmentPlanItem {
        WorkingTreatmentPlanItem(
            id: id,
            name: name,
            suggestedDose: suggestedDose
        )
    }
}

enum WorkingMapper {
    static func sessionDate(_ session: CDWorkingSession) throws -> Date {
        guard let date = session.date else {
            throw CoreDataWorkingMappingError.missingSessionDate(sessionID: (try session.requiredID()))
        }
        return date
    }

    static func queueAnimalID(from item: CDWorkingQueueItem) throws -> UUID {
        guard let animalID = item.animalIDSnapshot else {
            throw CoreDataWorkingMappingError.missingQueueAnimalID(queueItemID: (try item.requiredID()))
        }
        return animalID
    }

    static func makeSessionSummary(from session: CDWorkingSession) throws -> WorkingSessionSummary {
        let queueItems = managedQueueItems(session)
        for item in queueItems {
            _ = try queueAnimalID(from: item)
        }
        return WorkingSessionSummary(
            id: (try session.requiredID()),
            date: try sessionDate(session),
            status: try workingStatus(session),
            sourcePastureName: session.sourcePastureNameSnapshot,
            treatmentTemplateName: session.treatmentTemplateNameSnapshot,
            totalQueueItems: queueItems.count,
            completedQueueItems: try queueItems.filter {
                try queueStatus($0) == .done
            }.count
        )
    }

    static func makeSessionDetail(from session: CDWorkingSession) throws -> WorkingSessionDetailSnapshot {
        let queueItems = try managedQueueItems(session)
            .map(makeQueueItemSnapshot)
            .sorted(by: queueItemSort)

        return WorkingSessionDetailSnapshot(
            id: (try session.requiredID()),
            date: try sessionDate(session),
            status: try workingStatus(session),
            sourcePastureID: session.sourcePastureIDSnapshot,
            sourcePastureName: session.sourcePastureNameSnapshot,
            isSourcePastureAvailable: session.sourcePasture != nil,
            treatmentTemplateName: session.treatmentTemplateNameSnapshot,
            plannedTreatments: try plannedTreatments(session),
            queueItems: queueItems
        )
    }

    static func makeQueueItemSnapshot(from item: CDWorkingQueueItem) throws -> WorkingQueueItemSnapshot {
        let animalID = try queueAnimalID(from: item)
        return WorkingQueueItemSnapshot(
            id: (try item.requiredID()),
            status: try queueStatus(item),
            completedAt: item.completedAt,
            animalID: animalID,
            animalName: item.animalNameSnapshot,
            animalDisplayTagNumber: item.animalTagNumberSnapshot,
            animalDisplayTagColorID: item.animalTagColorIDSnapshot,
            animalDamDisplayTagNumber: item.animalDamDisplayTagNumberSnapshot,
            animalDamDisplayTagColorID: item.animalDamDisplayTagColorIDSnapshot,
            animalSex: try animalSex(item),
            collectedFromPastureID: item.collectedFromPastureIDSnapshot,
            collectedFromPastureName: item.collectedFromPastureNameSnapshot,
            destinationPastureID: item.destinationPastureIDSnapshot,
            destinationPastureName: item.destinationPastureNameSnapshot
        )
    }

    static func makeQueueItemEditorSnapshot(
        session: CDWorkingSession,
        queueItem: CDWorkingQueueItem,
        animal: CDAnimal
    ) throws -> WorkingQueueItemEditorSnapshot {
        let animalID = try queueAnimalID(from: queueItem)
        let plannedTreatments = try plannedTreatments(session)
        let treatmentRecords = try managedTreatmentRecords(session)
            .filter {
                try $0.animalIDSnapshot == animalID
                    && $0.animal?.id == animal.requiredID()
            }
            .map { record in (record: record, date: try treatmentDate(record)) }
            .sorted { lhs, rhs in
                let leftIndex = plannedTreatments.firstIndex { $0.id == lhs.record.treatmentItemID } ?? Int.max
                let rightIndex = plannedTreatments.firstIndex { $0.id == rhs.record.treatmentItemID } ?? Int.max
                if leftIndex != rightIndex {
                    return leftIndex < rightIndex
                }
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                return (try lhs.record.requiredID()).uuidString < (try rhs.record.requiredID()).uuidString
            }
            .map { try makeTreatmentRecordSnapshot(from: $0.record) }

        let pregnancyCheck = try managedPregnancyChecks(session)
            .filter { check in
                guard let linked = check.animal else {
                    throw CoreDataAnimalRepositoryError.missingPregnancyAnimalRelationship(
                        recordID: (try check.requiredID())
                    )
                }
                return (try linked.requiredID()) == (try animal.requiredID())
            }
            .map { check in
                (check: check, date: try CoreDataAnimalProjection.pregnancyDate(check))
            }
            .sorted {
                if $0.date != $1.date {
                    return $0.date > $1.date
                }
                return (try $0.check.requiredID()).uuidString < (try $1.check.requiredID()).uuidString
            }
            .first
            .map { try makePregnancyCheckSnapshot(from: $0.check) }

        let generatedHealth = try managedHealthRecords(session)
            .filter { record in
                guard let linked = record.animal else {
                    throw CoreDataAnimalRepositoryError.missingHealthAnimalRelationship(
                        recordID: (try record.requiredID())
                    )
                }
                return linked.id == animal.id
            }
            .map { record in
                (record, try CoreDataAnimalProjection.healthTreatment(record))
            }
        let observationNotes = generatedHealth.first {
            $0.1 == WorkingGeneratedHealthRecord.observation.treatmentName
        }?.0.notes ?? ""
        let castrationPerformed = generatedHealth.contains {
            $0.1 == WorkingGeneratedHealthRecord.castration.treatmentName
        }

        return WorkingQueueItemEditorSnapshot(
            id: (try queueItem.requiredID()),
            sessionID: (try session.requiredID()),
            sessionDate: try sessionDate(session),
            sessionStatus: try workingStatus(session),
            sessionSourcePastureName: session.sourcePastureNameSnapshot,
            plannedTreatments: plannedTreatments,
            status: try queueStatus(queueItem),
            completedAt: queueItem.completedAt,
            collectedFromPastureName: queueItem.collectedFromPastureNameSnapshot,
            destinationPastureID: queueItem.destinationPastureIDSnapshot,
            animalID: animalID,
            animalDisplayTagNumber: queueItem.animalTagNumberSnapshot,
            animalDisplayTagColorID: queueItem.animalTagColorIDSnapshot,
            animalDamDisplayTagNumber: queueItem.animalDamDisplayTagNumberSnapshot,
            animalDamDisplayTagColorID: queueItem.animalDamDisplayTagColorIDSnapshot,
            animalSex: try animalSex(queueItem),
            animalAgeInMonths: AnimalAgeFormatter.ageInMonths(from: try CoreDataAnimalProjection.birthDate(animal)),
            treatmentRecords: treatmentRecords,
            pregnancyCheck: pregnancyCheck,
            castrationPerformedInSession: castrationPerformed,
            observationNotes: observationNotes
        )
    }

    static func treatmentDate(_ record: CDWorkingTreatmentRecord) throws -> Date {
        guard let date = record.date else {
            throw CoreDataWorkingMappingError.missingTreatmentDate(recordID: (try record.requiredID()))
        }
        return date
    }

    static func makeTreatmentRecordSnapshot(
        from record: CDWorkingTreatmentRecord
    ) throws -> WorkingTreatmentRecordSnapshot {
        let date = try treatmentDate(record)
        let unit: WorkingTreatmentDoseUnit?
        if let rawValue = record.doseUnitRawValue {
            guard let decoded = WorkingTreatmentDoseUnit(rawValue: rawValue) else {
                throw CoreDataWorkingMappingError.invalidDoseUnit(
                    recordID: (try record.requiredID()),
                    value: rawValue
                )
            }
            unit = decoded
        } else {
            unit = nil
        }

        let route: WorkingTreatmentAdministrationRoute?
        if let rawValue = record.administrationRouteRawValue {
            guard let decoded = WorkingTreatmentAdministrationRoute(rawValue: rawValue) else {
                throw CoreDataWorkingMappingError.invalidAdministrationRoute(
                    recordID: (try record.requiredID()),
                    value: rawValue
                )
            }
            route = decoded
        } else {
            route = nil
        }

        guard let itemName = record.itemNameSnapshot,
              let treatmentItemID = record.treatmentItemID,
              record.animalIDSnapshot != nil else {
            throw CoreDataWorkingMappingError.corruptTreatmentRecord(recordID: (try record.requiredID()))
        }

        let dose = WorkingTreatmentDose(
            amount: record.doseAmount?.doubleValue,
            unit: unit,
            route: route
        )
        do {
            try WorkingTreatmentPlanRules.validate([
                WorkingTreatmentEntryInput(
                    date: date,
                    treatmentItemID: treatmentItemID,
                    itemName: itemName,
                    given: record.given,
                    dose: dose
                )
            ])
        } catch {
            throw CoreDataWorkingMappingError.corruptTreatmentRecord(recordID: (try record.requiredID()))
        }

        return WorkingTreatmentRecordSnapshot(
            id: (try record.requiredID()),
            date: date,
            treatmentItemID: treatmentItemID,
            itemName: itemName,
            given: record.given,
            dose: dose
        )
    }

    static func makePregnancyCheckSnapshot(
        from check: CDPregnancyCheck
    ) throws -> WorkingPregnancyCheckSnapshot {
        guard let rawValue = check.resultRawValue,
              let result = PregnancyResult(rawValue: rawValue) else {
            throw CoreDataWorkingMappingError.invalidPregnancyResult(
                checkID: (try check.requiredID()),
                value: check.resultRawValue ?? ""
            )
        }

        return WorkingPregnancyCheckSnapshot(
            date: try CoreDataAnimalProjection.pregnancyDate(check),
            result: result,
            estimatedDaysPregnant: check.estimatedDaysPregnant?.intValue,
            dueDate: check.dueDate,
            sire: try check.sire.map(CoreDataAnimalProjection.parentOption)
        )
    }

    static func plannedTreatments(_ session: CDWorkingSession) throws -> [WorkingTreatmentPlanItem] {
        guard let data = session.plannedTreatmentsData else {
            throw CoreDataWorkingMappingError.corruptPlannedTreatments(sessionID: (try session.requiredID()))
        }
        do {
            return try decodePersistedPlan(data)
        } catch {
            throw CoreDataWorkingMappingError.corruptPlannedTreatments(sessionID: (try session.requiredID()))
        }
    }

    static func treatmentTemplateName(_ template: CDWorkingTreatmentTemplate) throws -> String {
        guard let name = template.name else {
            throw CoreDataWorkingMappingError.corruptTreatmentTemplate(templateID: (try template.requiredID()))
        }
        return name
    }

    static func treatmentTemplateItems(
        _ template: CDWorkingTreatmentTemplate
    ) throws -> [WorkingTreatmentPlanItem] {
        guard let itemsData = template.itemsData else {
            throw CoreDataWorkingMappingError.corruptTreatmentTemplate(templateID: (try template.requiredID()))
        }
        do {
            return try decodePersistedPlan(itemsData)
        } catch {
            throw CoreDataWorkingMappingError.corruptTreatmentTemplate(templateID: (try template.requiredID()))
        }
    }

    private static func decodePersistedPlan(
        _ data: Data
    ) throws -> [WorkingTreatmentPlanItem] {
        let items = try JSONDecoder().decode(
            [CoreDataWorkingTreatmentPlanItemPayload].self,
            from: data
        ).map(\.domainValue)
        try WorkingTreatmentPlanRules.validate(items)
        return items
    }

    private static func workingStatus(_ session: CDWorkingSession) throws -> WorkingSessionStatus {
        guard let rawValue = session.statusRawValue,
              let status = WorkingSessionStatus(rawValue: rawValue) else {
            throw CoreDataWorkingMappingError.invalidSessionStatus(
                sessionID: (try session.requiredID()),
                value: session.statusRawValue
            )
        }
        return status
    }

    private static func queueStatus(_ item: CDWorkingQueueItem) throws -> WorkingQueueStatus {
        guard let rawValue = item.statusRawValue,
              let status = WorkingQueueStatus(rawValue: rawValue) else {
            throw CoreDataWorkingMappingError.invalidQueueStatus(
                queueItemID: (try item.requiredID()),
                value: item.statusRawValue
            )
        }
        return status
    }

    private static func animalSex(_ item: CDWorkingQueueItem) throws -> Sex {
        guard let sex = Sex(rawValue: item.animalSexRawValueSnapshot) else {
            throw CoreDataWorkingMappingError.invalidAnimalSex(
                queueItemID: (try item.requiredID()),
                value: item.animalSexRawValueSnapshot
            )
        }
        return sex
    }

    private static func queueItemSort(
        _ lhs: WorkingQueueItemSnapshot,
        _ rhs: WorkingQueueItemSnapshot
    ) -> Bool {
        let lhsTag = lhs.animalDisplayTagNumber ?? ""
        let rhsTag = rhs.animalDisplayTagNumber ?? ""
        let tagComparison = lhsTag.localizedStandardCompare(rhsTag)
        if tagComparison != .orderedSame {
            return tagComparison == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func managedQueueItems(_ session: CDWorkingSession) -> [CDWorkingQueueItem] {
        (session.queueItems?.allObjects as? [CDWorkingQueueItem]) ?? []
    }

    private static func managedTreatmentRecords(
        _ session: CDWorkingSession
    ) -> [CDWorkingTreatmentRecord] {
        (session.treatmentRecords?.allObjects as? [CDWorkingTreatmentRecord]) ?? []
    }

    private static func managedHealthRecords(_ session: CDWorkingSession) -> [CDHealthRecord] {
        (session.healthRecords?.allObjects as? [CDHealthRecord]) ?? []
    }

    private static func managedPregnancyChecks(_ session: CDWorkingSession) -> [CDPregnancyCheck] {
        (session.pregnancyChecks?.allObjects as? [CDPregnancyCheck]) ?? []
    }
}
