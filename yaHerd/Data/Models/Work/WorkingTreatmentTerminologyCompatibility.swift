import Foundation

// SwiftData and CloudKit field/entity names still use the original storage vocabulary.
// Domain and presentation code use treatment terminology; these adapters isolate storage compatibility.
typealias WorkingProtocolItem = WorkingTreatmentPlanItem

typealias WorkingProtocolTemplateSummary = WorkingTreatmentTemplateSummary
typealias WorkingProtocolTemplateDetailSnapshot = WorkingTreatmentTemplateDetailSnapshot
typealias WorkingProtocolTemplateListReader = WorkingTreatmentTemplateListReader
typealias WorkingProtocolTemplateDetailReader = WorkingTreatmentTemplateDetailReader
typealias WorkingProtocolTemplateCreating = WorkingTreatmentTemplateCreating
typealias WorkingProtocolTemplateUpdating = WorkingTreatmentTemplateUpdating
typealias WorkingProtocolTemplateDeleting = WorkingTreatmentTemplateDeleting
typealias WorkingProtocolTemplatesRepository = WorkingTreatmentTemplatesRepository
typealias WorkingProtocolTemplateEditorRepository = WorkingTreatmentTemplateEditorRepository

extension WorkingTreatmentTemplateSummary {
    init(id: UUID, name: String, itemCount: Int) {
        self.init(id: id, name: name, treatmentCount: itemCount)
    }

    var itemCount: Int { treatmentCount }
}

extension WorkingTreatmentTemplateDetailSnapshot {
    init(id: UUID, name: String, items: [WorkingTreatmentPlanItem]) {
        self.init(id: id, name: name, plannedTreatments: items)
    }

    var items: [WorkingTreatmentPlanItem] { plannedTreatments }
}

extension WorkingSessionSummary {
    init(
        id: UUID,
        date: Date,
        status: WorkingSessionStatus,
        sourcePastureName: String?,
        protocolName: String,
        totalQueueItems: Int,
        completedQueueItems: Int
    ) {
        self.init(
            id: id,
            date: date,
            status: status,
            sourcePastureName: sourcePastureName,
            treatmentTemplateName: protocolName,
            totalQueueItems: totalQueueItems,
            completedQueueItems: completedQueueItems
        )
    }

    var protocolName: String { treatmentTemplateName }
}

extension WorkingSessionDetailSnapshot {
    init(
        id: UUID,
        date: Date,
        status: WorkingSessionStatus,
        sourcePastureID: UUID?,
        sourcePastureName: String?,
        protocolName: String,
        protocolItems: [WorkingTreatmentPlanItem],
        queueItems: [WorkingQueueItemSnapshot]
    ) {
        self.init(
            id: id,
            date: date,
            status: status,
            sourcePastureID: sourcePastureID,
            sourcePastureName: sourcePastureName,
            treatmentTemplateName: protocolName,
            plannedTreatments: protocolItems,
            queueItems: queueItems
        )
    }

    var protocolName: String { treatmentTemplateName }
    var protocolItems: [WorkingTreatmentPlanItem] { plannedTreatments }
}

extension WorkingQueueItemEditorSnapshot {
    init(
        id: UUID,
        sessionID: UUID,
        sessionDate: Date,
        sessionStatus: WorkingSessionStatus,
        sessionSourcePastureName: String?,
        protocolItems: [WorkingTreatmentPlanItem],
        status: WorkingQueueStatus,
        completedAt: Date?,
        collectedFromPastureName: String?,
        destinationPastureID: UUID?,
        animalID: UUID?,
        animalDisplayTagNumber: String?,
        animalDisplayTagColorID: UUID?,
        animalDamDisplayTagNumber: String?,
        animalDamDisplayTagColorID: UUID?,
        animalSex: Sex,
        animalAgeInMonths: Int,
        treatmentRecords: [WorkingTreatmentRecordSnapshot],
        pregnancyCheck: WorkingPregnancyCheckSnapshot?,
        castrationPerformedInSession: Bool,
        observationNotes: String
    ) {
        self.init(
            id: id,
            sessionID: sessionID,
            sessionDate: sessionDate,
            sessionStatus: sessionStatus,
            sessionSourcePastureName: sessionSourcePastureName,
            plannedTreatments: protocolItems,
            status: status,
            completedAt: completedAt,
            collectedFromPastureName: collectedFromPastureName,
            destinationPastureID: destinationPastureID,
            animalID: animalID,
            animalDisplayTagNumber: animalDisplayTagNumber,
            animalDisplayTagColorID: animalDisplayTagColorID,
            animalDamDisplayTagNumber: animalDamDisplayTagNumber,
            animalDamDisplayTagColorID: animalDamDisplayTagColorID,
            animalSex: animalSex,
            animalAgeInMonths: animalAgeInMonths,
            treatmentRecords: treatmentRecords,
            pregnancyCheck: pregnancyCheck,
            castrationPerformedInSession: castrationPerformedInSession,
            observationNotes: observationNotes
        )
    }

    var protocolItems: [WorkingTreatmentPlanItem] { plannedTreatments }
}

extension DashboardWorkingSessionRecord {
    init(
        id: String,
        date: Date,
        isActive: Bool,
        sourcePastureName: String?,
        protocolName: String,
        totalQueueItems: Int,
        completedQueueItems: Int
    ) {
        self.init(
            id: id,
            date: date,
            isActive: isActive,
            sourcePastureName: sourcePastureName,
            treatmentTemplateName: protocolName,
            totalQueueItems: totalQueueItems,
            completedQueueItems: completedQueueItems
        )
    }

    var protocolName: String { treatmentTemplateName }
}

extension DashboardWorkingSessionSummary {
    init(
        id: String,
        date: Date,
        sourcePastureName: String?,
        protocolName: String,
        totalQueueItems: Int,
        completedQueueItems: Int
    ) {
        self.init(
            id: id,
            date: date,
            sourcePastureName: sourcePastureName,
            treatmentTemplateName: protocolName,
            totalQueueItems: totalQueueItems,
            completedQueueItems: completedQueueItems
        )
    }

    var protocolName: String { treatmentTemplateName }
}

extension HomeSnapshot {
    var hasWorkingProtocolTemplates: Bool { hasWorkingTreatmentTemplates }
}
