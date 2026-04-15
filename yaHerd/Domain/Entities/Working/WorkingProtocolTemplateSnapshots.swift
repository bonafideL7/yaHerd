import Foundation

struct WorkingProtocolTemplateSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let itemCount: Int
}

struct WorkingProtocolTemplateDetailSnapshot: Identifiable, Hashable {
    let id: UUID
    let name: String
    let items: [WorkingProtocolItem]
}

struct WorkingQueueDestinationAssignment: Hashable {
    let queueItemID: UUID
    let destinationPastureID: UUID?
}
