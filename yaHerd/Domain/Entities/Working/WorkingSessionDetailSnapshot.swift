import Foundation

struct WorkingQueueItemSnapshot: Identifiable, Hashable {
    let id: UUID
    let queueOrder: Int
    let status: WorkingQueueStatus
    let completedAt: Date?
    let animalID: UUID?
    let animalDisplayTagNumber: String?
    let animalDisplayTagColorID: UUID?
    let animalSex: Sex
    let collectedFromPastureName: String?
    let destinationPastureID: UUID?
    let destinationPastureName: String?
}

struct WorkingSessionDetailSnapshot: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let status: WorkingSessionStatus
    let sourcePastureID: UUID?
    let sourcePastureName: String?
    let protocolName: String
    let protocolItems: [WorkingProtocolItem]
    let queueItems: [WorkingQueueItemSnapshot]

    var queuedCount: Int {
        queueItems.filter { $0.status == .queued || $0.status == .inProgress }.count
    }

    var doneCount: Int {
        queueItems.filter { $0.status == .done }.count
    }
}
