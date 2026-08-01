//
//  WorkingSession.swift
//  yaHerd
//

import SwiftData
import Foundation

/// A working session represents a run through the working pen (shots / preg check / castration / observations)
/// for a collected lot of animals.
extension YaHerdSchemaV1 {
    @Model
    final class WorkingSession {
        #Index<WorkingSession>(
            [\.statusRawValue],
            [\.date],
            [\.statusRawValue, \.date]
        )

        var publicID: UUID = UUID()
        @Relationship(deleteRule: .nullify) var herd: Herd?
        var date: Date = Date.now
        var statusRawValue: String = WorkingSessionStatus.active.rawValue

        /// Convenience reference for the common case where the lot is collected from one pasture.
        /// (Working pen is not a pasture.)
        @Relationship(deleteRule: .nullify)
        var sourcePasture: Pasture?

        /// Stored field name retained in V1; domain and presentation use treatment-template terminology.
        var protocolName: String = ""
        /// Planned treatments captured as a session snapshot.
        var protocolItems: [WorkingProtocolItem] = []

        /// Deprecated V1 storage compatibility field. The current animal workflow
        /// no longer has a queue pointer and must not depend on this value.
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

        var status: WorkingSessionStatus {
            get { WorkingSessionStatus(rawValue: statusRawValue) ?? .active }
            set { statusRawValue = newValue.rawValue }
        }

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
            self.statusRawValue = status.rawValue
            self.sourcePasture = sourcePasture
            self.protocolName = protocolName
            self.protocolItems = protocolItems
            self.currentQueueIndex = 0
            self.notes = notes
        }
    }
}

enum WorkingSessionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case finished
    case cancelled
}
