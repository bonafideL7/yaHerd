//
//  WorkingSession.swift
//  yaHerd
//

import SwiftData
import Foundation

/// A working session represents a run through the working pen (shots / preg check / castration / observations)
/// for a collected lot of animals.
@Model
final class WorkingSession {
    var publicID: UUID = UUID()
    var date: Date = Date.now
    var status: WorkingSessionStatus = WorkingSessionStatus.active

    /// Convenience reference for the common case where the lot is collected from one pasture.
    /// (Working pen is not a pasture.)
    @Relationship(deleteRule: .nullify)
    var sourcePasture: Pasture?

    /// Protocol name displayed in the UI.
    var protocolName: String = ""
    /// Predetermined work items (shots) for this session.
    var protocolItems: [WorkingProtocolItem] = []

    /// Pointer into the queue for chute mode.
    var currentQueueIndex: Int = 0
    var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \WorkingQueueItem.session)
    var queueItemStorage: [WorkingQueueItem]?

    @Relationship(deleteRule: .nullify, inverse: \Animal.activeWorkingSession)
    var activeAnimalStorage: [Animal]?

    @Relationship(deleteRule: .nullify, inverse: \HealthRecord.workingSession)
    var healthRecordStorage: [HealthRecord]?

    @Relationship(deleteRule: .nullify, inverse: \PregnancyCheck.workingSession)
    var pregnancyCheckStorage: [PregnancyCheck]?

    @Relationship(deleteRule: .nullify, inverse: \WorkingTreatmentRecord.session)
    var treatmentRecordStorage: [WorkingTreatmentRecord]?

    var queueItems: [WorkingQueueItem] {
        get { queueItemStorage ?? [] }
        set { queueItemStorage = newValue }
    }

    init(
        publicID: UUID = UUID(),
        date: Date = Date.now,
        status: WorkingSessionStatus = WorkingSessionStatus.active,
        sourcePasture: Pasture? = nil,
        protocolName: String,
        protocolItems: [WorkingProtocolItem],
        notes: String? = nil
    ) {
        self.publicID = publicID
        self.date = date
        self.status = status
        self.sourcePasture = sourcePasture
        self.protocolName = protocolName
        self.protocolItems = protocolItems
        self.currentQueueIndex = 0
        self.notes = notes
    }
}

enum WorkingSessionStatus: String, Codable, CaseIterable {
    case active
    case finished
    case cancelled
}

/// Codable protocol item stored inside a WorkingSession or template.
struct WorkingProtocolItem: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var defaultQuantity: Double?

    init(id: UUID = UUID(), name: String, defaultQuantity: Double? = nil) {
        self.id = id
        self.name = name
        self.defaultQuantity = defaultQuantity
    }
}
