//
//  WorkingQueueItem.swift
//  yaHerd
//

import SwiftData
import Foundation

@Model
final class WorkingQueueItem {
    @Attribute(.unique) var publicID: UUID
    var queueOrder: Int
    var status: WorkingQueueStatus
    var completedAt: Date?

    /// Where this animal was collected from (for future multi-source sessions).
    @Relationship(deleteRule: .nullify)
    var collectedFromPasture: Pasture?

    /// Destination pasture when returning animals at the end of a session.
    @Relationship(deleteRule: .nullify)
    var destinationPasture: Pasture?

    var workNotes: String?

    @Relationship(deleteRule: .nullify)
    var animal: Animal?

    @Relationship(inverse: \WorkingSession.queueItems)
    var session: WorkingSession

    init(
        publicID: UUID = UUID(),
        queueOrder: Int,
        status: WorkingQueueStatus = .queued,
        collectedFromPasture: Pasture? = nil,
        destinationPasture: Pasture? = nil,
        workNotes: String? = nil,
        animal: Animal,
        session: WorkingSession
    ) {
        self.publicID = publicID
        self.queueOrder = queueOrder
        self.status = status
        self.completedAt = nil
        self.collectedFromPasture = collectedFromPasture
        self.destinationPasture = destinationPasture
        self.workNotes = workNotes
        self.animal = animal
        self.session = session
    }
}

enum WorkingQueueStatus: String, Codable, CaseIterable {
    case queued
    case inProgress
    case done
    case skipped
}
