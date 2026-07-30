import Foundation

struct WorkingSessionSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let status: WorkingSessionStatus
    let sourcePastureName: String?
    let treatmentTemplateName: String
    let totalQueueItems: Int
    let completedQueueItems: Int
}
