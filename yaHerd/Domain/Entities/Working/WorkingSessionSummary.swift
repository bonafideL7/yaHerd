import Foundation

struct WorkingSessionSummary: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let status: WorkingSessionStatus
    let sourcePastureName: String?
    let protocolName: String
    let totalQueueItems: Int
    let completedQueueItems: Int
}
