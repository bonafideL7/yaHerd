//
//  Herd.swift
//  yaHerd
//

import Foundation
import SwiftData

/// Top-level ownership and query scope for the local herd data graph.
///
/// Every herd-owned record points back to this root so repositories can keep
/// data consistently scoped without exposing persistence-specific identity.
extension YaHerdSchemaV1 {
    @Model
    final class Herd {
        var publicID: UUID = UUID()
        var name: String = ""
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now

        // Legacy SwiftData V1 storage field retained to keep the persisted schema stable.
        // It is not Domain state and must not be carried into the Core Data model.
        var schemaVersion: Int = 1

        @Relationship(deleteRule: .nullify, inverse: \Animal.herd)
        var animalStorage: [Animal]?

        @Relationship(deleteRule: .nullify, inverse: \AnimalTag.herd)
        var animalTagStorage: [AnimalTag]?

        @Relationship(deleteRule: .nullify, inverse: \AnimalStatusReference.herd)
        var animalStatusReferenceStorage: [AnimalStatusReference]?

        @Relationship(deleteRule: .nullify, inverse: \StatusRecord.herd)
        var statusRecordStorage: [StatusRecord]?

        @Relationship(deleteRule: .nullify, inverse: \HealthRecord.herd)
        var healthRecordStorage: [HealthRecord]?

        @Relationship(deleteRule: .nullify, inverse: \PregnancyCheck.herd)
        var pregnancyCheckStorage: [PregnancyCheck]?

        @Relationship(deleteRule: .nullify, inverse: \MovementRecord.herd)
        var movementRecordStorage: [MovementRecord]?

        @Relationship(deleteRule: .nullify, inverse: \Pasture.herd)
        var pastureStorage: [Pasture]?

        @Relationship(deleteRule: .nullify, inverse: \PastureGroup.herd)
        var pastureGroupStorage: [PastureGroup]?

        @Relationship(deleteRule: .nullify, inverse: \TagColorDefinition.herd)
        var tagColorDefinitionStorage: [TagColorDefinition]?

        @Relationship(deleteRule: .nullify, inverse: \WorkingSession.herd)
        var workingSessionStorage: [WorkingSession]?

        @Relationship(deleteRule: .nullify, inverse: \WorkingQueueItem.herd)
        var workingQueueItemStorage: [WorkingQueueItem]?

        @Relationship(deleteRule: .nullify, inverse: \WorkingTreatmentRecord.herd)
        var workingTreatmentRecordStorage: [WorkingTreatmentRecord]?

        @Relationship(deleteRule: .nullify, inverse: \WorkingProtocolTemplate.herd)
        var workingProtocolTemplateStorage: [WorkingProtocolTemplate]?

        @Relationship(deleteRule: .nullify, inverse: \FieldCheckSession.herd)
        var fieldCheckSessionStorage: [FieldCheckSession]?

        @Relationship(deleteRule: .nullify, inverse: \FieldCheckAnimalCheck.herd)
        var fieldCheckAnimalCheckStorage: [FieldCheckAnimalCheck]?

        @Relationship(deleteRule: .nullify, inverse: \FieldCheckFinding.herd)
        var fieldCheckFindingStorage: [FieldCheckFinding]?

        init(
            publicID: UUID = UUID(),
            name: String,
            createdAt: Date = Date.now,
            updatedAt: Date = Date.now,
            schemaVersion: Int = 1
        ) {
            self.publicID = publicID
            self.name = name
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.schemaVersion = schemaVersion
        }

        func rename(to name: String) {
            self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            self.updatedAt = .now
        }
    }
}
