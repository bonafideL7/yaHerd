import Foundation

struct WorkingTreatmentTemplateSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let treatmentCount: Int
}

struct WorkingTreatmentTemplateDetailSnapshot: Identifiable, Hashable {
    let id: UUID
    let name: String
    let plannedTreatments: [WorkingTreatmentPlanItem]
}

struct WorkingQueueDestinationAssignment: Hashable {
    let queueItemID: UUID
    let destinationPastureID: UUID?
}
