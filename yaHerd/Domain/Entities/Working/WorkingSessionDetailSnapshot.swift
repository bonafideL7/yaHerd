import Foundation

struct WorkingQueueItemSnapshot: Identifiable, Hashable {
    let id: UUID
    let status: WorkingQueueStatus
    let completedAt: Date?
    let animalID: UUID?
    let animalName: String?
    let animalDisplayTagNumber: String?
    let animalDisplayTagColorID: UUID?
    let animalDamDisplayTagNumber: String?
    let animalDamDisplayTagColorID: UUID?
    let animalSex: Sex
    let collectedFromPastureID: UUID?
    let collectedFromPastureName: String?
    let destinationPastureID: UUID?
    let destinationPastureName: String?

    /// Compatibility initializer for the outgoing live-relationship mapper.
    ///
    /// The legacy mapper never persisted the new historical name/collected-from UUID fields.
    /// Target Core Data mapping must use the full initializer below.
    init(
        id: UUID,
        status: WorkingQueueStatus,
        completedAt: Date?,
        animalID: UUID?,
        animalDisplayTagNumber: String?,
        animalDisplayTagColorID: UUID?,
        animalDamDisplayTagNumber: String?,
        animalDamDisplayTagColorID: UUID?,
        animalSex: Sex,
        collectedFromPastureName: String?,
        destinationPastureID: UUID?,
        destinationPastureName: String?
    ) {
        self.id = id
        self.status = status
        self.completedAt = completedAt
        self.animalID = animalID
        self.animalName = nil
        self.animalDisplayTagNumber = animalDisplayTagNumber
        self.animalDisplayTagColorID = animalDisplayTagColorID
        self.animalDamDisplayTagNumber = animalDamDisplayTagNumber
        self.animalDamDisplayTagColorID = animalDamDisplayTagColorID
        self.animalSex = animalSex
        self.collectedFromPastureID = nil
        self.collectedFromPastureName = collectedFromPastureName
        self.destinationPastureID = destinationPastureID
        self.destinationPastureName = destinationPastureName
    }

    /// Target-persistence initializer. All captured historical display/relationship identity
    /// fields are explicit so a Core Data mapper cannot silently fall back to live relationships.
    /// New Core Data queue rows always capture the Animal UUID, name, and display tag; the optional
    /// stored properties exist only so the outgoing live-relationship projection remains compatible.
    init(
        id: UUID,
        status: WorkingQueueStatus,
        completedAt: Date?,
        animalID: UUID,
        animalName: String,
        animalDisplayTagNumber: String,
        animalDisplayTagColorID: UUID?,
        animalDamDisplayTagNumber: String?,
        animalDamDisplayTagColorID: UUID?,
        animalSex: Sex,
        collectedFromPastureID: UUID?,
        collectedFromPastureName: String?,
        destinationPastureID: UUID?,
        destinationPastureName: String?
    ) {
        self.id = id
        self.status = status
        self.completedAt = completedAt
        self.animalID = animalID
        self.animalName = animalName
        self.animalDisplayTagNumber = animalDisplayTagNumber
        self.animalDisplayTagColorID = animalDisplayTagColorID
        self.animalDamDisplayTagNumber = animalDamDisplayTagNumber
        self.animalDamDisplayTagColorID = animalDamDisplayTagColorID
        self.animalSex = animalSex
        self.collectedFromPastureID = collectedFromPastureID
        self.collectedFromPastureName = collectedFromPastureName
        self.destinationPastureID = destinationPastureID
        self.destinationPastureName = destinationPastureName
    }
}

struct WorkingSessionDetailSnapshot: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let status: WorkingSessionStatus
    /// Historical source-pasture application identity captured for the session.
    /// This may remain non-nil after the live Pasture relationship is deleted.
    let sourcePastureID: UUID?
    let sourcePastureName: String?
    /// Whether the historical source still resolves to a live Pasture that can be used
    /// for collection or as a destination.
    let isSourcePastureAvailable: Bool
    let treatmentTemplateName: String
    let plannedTreatments: [WorkingTreatmentPlanItem]
    let queueItems: [WorkingQueueItemSnapshot]

    /// Compatibility initializer for the outgoing live-relationship mapper.
    ///
    /// The legacy mapper only supplies a source UUID while its live Pasture relationship exists,
    /// so availability can be derived safely there. Core Data historical mappers must use the
    /// explicit initializer below because a captured source UUID may outlive the live relationship.
    init(
        id: UUID,
        date: Date,
        status: WorkingSessionStatus,
        sourcePastureID: UUID?,
        sourcePastureName: String?,
        treatmentTemplateName: String,
        plannedTreatments: [WorkingTreatmentPlanItem],
        queueItems: [WorkingQueueItemSnapshot]
    ) {
        self.init(
            id: id,
            date: date,
            status: status,
            sourcePastureID: sourcePastureID,
            sourcePastureName: sourcePastureName,
            isSourcePastureAvailable: sourcePastureID != nil,
            treatmentTemplateName: treatmentTemplateName,
            plannedTreatments: plannedTreatments,
            queueItems: queueItems
        )
    }

    /// Target-persistence initializer. Historical source identity and current live availability
    /// are deliberately independent values.
    init(
        id: UUID,
        date: Date,
        status: WorkingSessionStatus,
        sourcePastureID: UUID?,
        sourcePastureName: String?,
        isSourcePastureAvailable: Bool,
        treatmentTemplateName: String,
        plannedTreatments: [WorkingTreatmentPlanItem],
        queueItems: [WorkingQueueItemSnapshot]
    ) {
        self.id = id
        self.date = date
        self.status = status
        self.sourcePastureID = sourcePastureID
        self.sourcePastureName = sourcePastureName
        self.isSourcePastureAvailable = isSourcePastureAvailable
        self.treatmentTemplateName = treatmentTemplateName
        self.plannedTreatments = plannedTreatments
        self.queueItems = queueItems
    }

    var queuedCount: Int {
        queueItems.filter { $0.status == .queued || $0.status == .inProgress }.count
    }

    var doneCount: Int {
        queueItems.filter { $0.status == .done }.count
    }
}
