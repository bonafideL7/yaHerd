import Foundation

enum WorkingMapper {
    static func makeSessionSummary(from session: WorkingSession) -> WorkingSessionSummary {
        WorkingSessionSummary(
            id: session.publicID,
            date: session.date,
            status: session.status,
            sourcePastureName: session.sourcePasture?.name,
            protocolName: session.protocolName,
            totalQueueItems: session.queueItems.count,
            completedQueueItems: session.queueItems.filter { $0.status == .done }.count
        )
    }

    static func makeSessionDetail(from session: WorkingSession) -> WorkingSessionDetailSnapshot {
        WorkingSessionDetailSnapshot(
            id: session.publicID,
            date: session.date,
            status: session.status,
            sourcePastureID: session.sourcePasture?.publicID,
            sourcePastureName: session.sourcePasture?.name,
            protocolName: session.protocolName,
            protocolItems: session.protocolItems,
            queueItems: session.queueItems
                .sorted(by: { $0.queueOrder < $1.queueOrder })
                .map(makeQueueItemSnapshot)
        )
    }

    static func makeQueueItemSnapshot(from item: WorkingQueueItem) -> WorkingQueueItemSnapshot {
        WorkingQueueItemSnapshot(
            id: item.publicID,
            queueOrder: item.queueOrder,
            status: item.status,
            completedAt: item.completedAt,
            animalID: item.animal?.publicID,
            animalDisplayTagNumber: item.animal?.displayTagNumber,
            animalDisplayTagColorID: item.animal?.displayTagColorID,
            animalSex: item.animal?.sex ?? .unknown,
            collectedFromPastureName: item.collectedFromPasture?.name,
            destinationPastureID: item.destinationPasture?.publicID,
            destinationPastureName: item.destinationPasture?.name
        )
    }

    static func makeTemplateSummary(from template: WorkingProtocolTemplate) -> WorkingProtocolTemplateSummary {
        WorkingProtocolTemplateSummary(
            id: template.publicID,
            name: template.name,
            itemCount: template.items.count
        )
    }

    static func makeTemplateDetail(from template: WorkingProtocolTemplate) -> WorkingProtocolTemplateDetailSnapshot {
        WorkingProtocolTemplateDetailSnapshot(
            id: template.publicID,
            name: template.name,
            items: template.items
        )
    }

    static func makeTreatmentRecordSnapshot(from record: WorkingTreatmentRecord) -> WorkingTreatmentRecordSnapshot {
        WorkingTreatmentRecordSnapshot(
            id: UUID(),
            date: record.date,
            itemName: record.itemName,
            given: record.given,
            quantity: record.quantity
        )
    }

    static func makePregnancyCheckSnapshot(from check: PregnancyCheck) -> WorkingPregnancyCheckSnapshot {
        WorkingPregnancyCheckSnapshot(
            date: check.date,
            result: check.result,
            estimatedDaysPregnant: check.estimatedDaysPregnant,
            dueDate: check.dueDate,
            sire: check.sireAnimal.map { sire in
                AnimalParentOption(
                    id: sire.publicID,
                    displayTagNumber: sire.displayTagNumber,
                    displayTagColorID: sire.displayTagColorID,
                    sex: sire.sex ?? .unknown,
                    isArchived: sire.isArchived
                )
            }
        )
    }

    static func makeQueueItemEditorSnapshot(session: WorkingSession, queueItem: WorkingQueueItem, animal: Animal, treatmentRecords: [WorkingTreatmentRecordSnapshot], pregnancyCheck: WorkingPregnancyCheckSnapshot?, castrationPerformed: Bool, observationNotes: String) -> WorkingQueueItemEditorSnapshot {
        WorkingQueueItemEditorSnapshot(
            id: queueItem.publicID,
            sessionID: session.publicID,
            sessionDate: session.date,
            sessionSourcePastureName: session.sourcePasture?.name,
            protocolItems: session.protocolItems,
            status: queueItem.status,
            completedAt: queueItem.completedAt,
            collectedFromPastureName: queueItem.collectedFromPasture?.name,
            destinationPastureID: queueItem.destinationPasture?.publicID,
            animalID: animal.publicID,
            animalDisplayTagNumber: animal.displayTagNumber,
            animalDisplayTagColorID: animal.displayTagColorID,
            animalSex: animal.sex ?? .unknown,
            animalAgeInMonths: animal.ageInMonths,
            treatmentRecords: treatmentRecords,
            pregnancyCheck: pregnancyCheck,
            castrationPerformedInSession: castrationPerformed,
            observationNotes: observationNotes
        )
    }
}
