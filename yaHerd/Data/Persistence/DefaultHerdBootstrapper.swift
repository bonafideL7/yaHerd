//
//  DefaultHerdBootstrapper.swift
//  yaHerd
//

import Foundation
import SwiftData

/// Creates the single local herd scope used by the current app and attaches
/// existing unscoped records to it. This is the first migration step toward
/// sharing a herd as one CloudKit collaboration unit.
enum DefaultHerdBootstrapper {
    static let defaultHerdName = "My Herd"
    private static let currentMigrationVersion = 1
    private static let migrationVersionKeyPrefix = "DefaultHerdBootstrapper.completedMigrationVersion"

    static func ensureDefaultHerd(in context: ModelContext) throws {
        let herd = try defaultHerd(in: context)
        let changed = try attachAllUnscopedRecords(in: context, to: herd)
        try save(context, herd: herd, changed: changed)
    }

    static func ensureDefaultHerdForAppLaunch(
        in context: ModelContext,
        storageScope: String,
        migrationState: UserDefaults = .standard
    ) throws {
        let herd = try defaultHerd(in: context)
        let migrationVersionKey = "\(migrationVersionKeyPrefix).\(storageScope)"
        let shouldRunMigration = migrationState.integer(forKey: migrationVersionKey) < currentMigrationVersion
        var changed = false

        if shouldRunMigration {
            changed = try attachAllUnscopedRecords(in: context, to: herd)
        }

        try save(context, herd: herd, changed: changed)

        if shouldRunMigration {
            migrationState.set(currentMigrationVersion, forKey: migrationVersionKey)
        }
    }

    static func defaultHerd(in context: ModelContext) throws -> Herd {
        var descriptor = FetchDescriptor<Herd>(
            sortBy: [SortDescriptor(\Herd.createdAt)]
        )
        descriptor.fetchLimit = 1

        if let herd = try context.fetch(descriptor).first {
            return herd
        }

        let herd = Herd(name: defaultHerdName)
        context.insert(herd)
        return herd
    }

    private static func attachAllUnscopedRecords(in context: ModelContext, to herd: Herd) throws -> Bool {
        var changed = false

        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<Animal>(predicate: #Predicate<Animal> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \Animal.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<AnimalTag>(predicate: #Predicate<AnimalTag> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \AnimalTag.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<AnimalStatusReference>(predicate: #Predicate<AnimalStatusReference> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \AnimalStatusReference.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<StatusRecord>(predicate: #Predicate<StatusRecord> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \StatusRecord.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<HealthRecord>(predicate: #Predicate<HealthRecord> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \HealthRecord.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<PregnancyCheck>(predicate: #Predicate<PregnancyCheck> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \PregnancyCheck.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<MovementRecord>(predicate: #Predicate<MovementRecord> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \MovementRecord.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<Pasture>(predicate: #Predicate<Pasture> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \Pasture.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<PastureGroup>(predicate: #Predicate<PastureGroup> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \PastureGroup.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<TagColorDefinition>(predicate: #Predicate<TagColorDefinition> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \TagColorDefinition.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<WorkingSession>(predicate: #Predicate<WorkingSession> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \WorkingSession.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<WorkingQueueItem>(predicate: #Predicate<WorkingQueueItem> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \WorkingQueueItem.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<WorkingTreatmentRecord>(predicate: #Predicate<WorkingTreatmentRecord> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \WorkingTreatmentRecord.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<WorkingProtocolTemplate>(predicate: #Predicate<WorkingProtocolTemplate> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \WorkingProtocolTemplate.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<FieldCheckSession>(predicate: #Predicate<FieldCheckSession> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \FieldCheckSession.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<FieldCheckAnimalCheck>(predicate: #Predicate<FieldCheckAnimalCheck> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \FieldCheckAnimalCheck.herd
        ) || changed
        changed = try attachUnscopedRecords(
            matching: FetchDescriptor<FieldCheckFinding>(predicate: #Predicate<FieldCheckFinding> { $0.herd == nil }),
            in: context,
            to: herd,
            keyPath: \FieldCheckFinding.herd
        ) || changed

        return changed
    }

    private static func attachUnscopedRecords<Model: PersistentModel>(
        matching descriptor: FetchDescriptor<Model>,
        in context: ModelContext,
        to herd: Herd,
        keyPath: WritableKeyPath<Model, Herd?>
    ) throws -> Bool {
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return false }

        for var record in records {
            record[keyPath: keyPath] = herd
        }

        return true
    }

    private static func save(_ context: ModelContext, herd: Herd, changed: Bool) throws {
        if changed {
            herd.updatedAt = .now
        }

        guard changed || context.hasChanges else { return }
        try PersistenceLog.save(context, operation: "DefaultHerdBootstrapper")
    }
}
