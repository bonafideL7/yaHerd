@preconcurrency import CoreData
import Foundation

enum CoreDataWorkingMappingError: Error, Equatable {
    case invalidSessionStatus(sessionID: UUID, value: String)
    case invalidQueueStatus(queueItemID: UUID, value: String)
    case invalidAnimalSex(queueItemID: UUID, value: String)
    case invalidPregnancyResult(checkID: UUID, value: String)
    case invalidDoseUnit(recordID: UUID, value: String)
    case invalidAdministrationRoute(recordID: UUID, value: String)
    case corruptPlannedTreatments(sessionID: UUID)
    case corruptTreatmentRecord(recordID: UUID)
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

extension WorkingMapper {
    static func makeSessionSummary(from session: CDWorkingSession) throws -> WorkingSessionSummary {
        let queueItems = managedQueueItems(session)
        return WorkingSessionSummary(
            id: session.id,
            date: session.date,
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
            id: session.id,
            date: session.date,
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
        WorkingQueueItemSnapshot(
            id: item.id,
            status: try queueStatus(item),
            completedAt: item.completedAt,
            animalID: item.animalIDSnapshot,
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
        let plannedTreatments = try plannedTreatments(session)
        let treatmentRecords = try managedTreatmentRecords(session)
            .filter {
                $0.animalIDSnapshot == queueItem.animalIDSnapshot
                    && $0.animal?.id == animal.id
            }
            .sorted { lhs, rhs in
                let leftIndex = plannedTreatments.firstIndex { $0.id == lhs.treatmentItemID } ?? Int.max
                let rightIndex = plannedTreatments.firstIndex { $0.id == rhs.treatmentItemID } ?? Int.max
                if leftIndex != rightIndex {
                    return leftIndex < rightIndex
                }
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(makeTreatmentRecordSnapshot)

        let pregnancyCheck = try managedPregnancyChecks(session)
            .filter { $0.animal.id == animal.id }
            .sorted {
                if $0.date != $1.date {
                    return $0.date > $1.date
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first
            .map(makePregnancyCheckSnapshot)

        let generatedHealth = managedHealthRecords(session).filter {
            $0.animal.id == animal.id
        }
        let observationNotes = generatedHealth.first {
            $0.treatment == WorkingGeneratedHealthRecord.observation.treatmentName
        }?.notes ?? ""
        let castrationPerformed = generatedHealth.contains {
            $0.treatment == WorkingGeneratedHealthRecord.castration.treatmentName
        }

        return WorkingQueueItemEditorSnapshot(
            id: queueItem.id,
            sessionID: session.id,
            sessionDate: session.date,
            sessionStatus: try workingStatus(session),
            sessionSourcePastureName: session.sourcePastureNameSnapshot,
            plannedTreatments: plannedTreatments,
            status: try queueStatus(queueItem),
            completedAt: queueItem.completedAt,
            collectedFromPastureName: queueItem.collectedFromPastureNameSnapshot,
            destinationPastureID: queueItem.destinationPastureIDSnapshot,
            animalID: queueItem.animalIDSnapshot,
            animalDisplayTagNumber: queueItem.animalTagNumberSnapshot,
            animalDisplayTagColorID: queueItem.animalTagColorIDSnapshot,
            animalDamDisplayTagNumber: queueItem.animalDamDisplayTagNumberSnapshot,
            animalDamDisplayTagColorID: queueItem.animalDamDisplayTagColorIDSnapshot,
            animalSex: try animalSex(queueItem),
            animalAgeInMonths: AnimalAgeFormatter.ageInMonths(from: animal.birthDate),
            treatmentRecords: treatmentRecords,
            pregnancyCheck: pregnancyCheck,
            castrationPerformedInSession: castrationPerformed,
            observationNotes: observationNotes
        )
    }

    static func makeTreatmentRecordSnapshot(
        from record: CDWorkingTreatmentRecord
    ) throws -> WorkingTreatmentRecordSnapshot {
        let unit: WorkingTreatmentDoseUnit?
        if let rawValue = record.doseUnitRawValue {
            guard let decoded = WorkingTreatmentDoseUnit(rawValue: rawValue) else {
                throw CoreDataWorkingMappingError.invalidDoseUnit(
                    recordID: record.id,
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
                    recordID: record.id,
                    value: rawValue
                )
            }
            route = decoded
        } else {
            route = nil
        }

        let dose = WorkingTreatmentDose(
            amount: record.doseAmount?.doubleValue,
            unit: unit,
            route: route
        )
        do {
            try WorkingTreatmentPlanRules.validate([
                WorkingTreatmentEntryInput(
                    date: record.date,
                    treatmentItemID: record.treatmentItemID,
                    itemName: record.itemNameSnapshot,
                    given: record.given,
                    dose: dose
                )
            ])
        } catch {
            throw CoreDataWorkingMappingError.corruptTreatmentRecord(recordID: record.id)
        }

        return WorkingTreatmentRecordSnapshot(
            id: record.id,
            date: record.date,
            treatmentItemID: record.treatmentItemID,
            itemName: record.itemNameSnapshot,
            given: record.given,
            dose: dose
        )
    }

    static func makePregnancyCheckSnapshot(
        from check: CDPregnancyCheck
    ) throws -> WorkingPregnancyCheckSnapshot {
        guard let result = PregnancyResult(rawValue: check.resultRawValue) else {
            throw CoreDataWorkingMappingError.invalidPregnancyResult(
                checkID: check.id,
                value: check.resultRawValue
            )
        }

        return WorkingPregnancyCheckSnapshot(
            date: check.date,
            result: result,
            estimatedDaysPregnant: check.estimatedDaysPregnant?.intValue,
            dueDate: check.dueDate,
            sire: try check.sire.map(CoreDataAnimalProjection.parentOption)
        )
    }

    static func plannedTreatments(_ session: CDWorkingSession) throws -> [WorkingTreatmentPlanItem] {
        do {
            let items = try JSONDecoder().decode(
                [CoreDataWorkingTreatmentPlanItemPayload].self,
                from: session.plannedTreatmentsData
            )
            .map(\.domainValue)
            try WorkingTreatmentPlanRules.validate(items)
            return items
        } catch {
            throw CoreDataWorkingMappingError.corruptPlannedTreatments(sessionID: session.id)
        }
    }

    private static func workingStatus(_ session: CDWorkingSession) throws -> WorkingSessionStatus {
        guard let status = WorkingSessionStatus(rawValue: session.statusRawValue) else {
            throw CoreDataWorkingMappingError.invalidSessionStatus(
                sessionID: session.id,
                value: session.statusRawValue
            )
        }
        return status
    }

    private static func queueStatus(_ item: CDWorkingQueueItem) throws -> WorkingQueueStatus {
        guard let status = WorkingQueueStatus(rawValue: item.statusRawValue) else {
            throw CoreDataWorkingMappingError.invalidQueueStatus(
                queueItemID: item.id,
                value: item.statusRawValue
            )
        }
        return status
    }

    private static func animalSex(_ item: CDWorkingQueueItem) throws -> Sex {
        guard let sex = Sex(rawValue: item.animalSexRawValueSnapshot) else {
            throw CoreDataWorkingMappingError.invalidAnimalSex(
                queueItemID: item.id,
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
