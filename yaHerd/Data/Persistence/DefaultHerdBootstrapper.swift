//
//  DefaultHerdBootstrapper.swift
//  yaHerd
//

import Foundation
import SwiftData

/// Creates the single local herd scope used by the current app and attaches
/// existing unscoped records to it. This is the first migration step toward
/// sharing a herd as one CloudKit collaboration unit.
@MainActor
enum DefaultHerdBootstrapper {
    nonisolated static let defaultHerdName = "My Herd"
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
        migrationState: UserDefaults = .standard,
        mutationGate: HerdDataMutationGate = HerdDataMutationGate()
    ) throws {
        // The durable repair gate must be loaded before this startup writer does anything.
        // A pending or unreadable repair journal means public IDs may be between the local
        // commit and shared-bridge convergence phases, so creating/re-scoping records here
        // would mutate the graph outside the repair transaction. Defer until a later launch.
        guard !mutationGate.requiresBridgeConvergence else { return }

        let migrationVersionKey = "\(migrationVersionKeyPrefix).\(storageScope)"
        let shouldRunMigration = migrationState.integer(forKey: migrationVersionKey) < currentMigrationVersion

        // A pristine installation must stay physically empty. Creating a Herd here used to
        // manufacture a new CloudKit-backed row before an existing iCloud store had time to
        // import. Reinstalling the app therefore accumulated one extra bootstrap Herd per install.
        // Only create the migration Herd when there is actual legacy data that needs a scope.
        let herd: Herd
        if let existingHerd = try existingDefaultHerd(in: context) {
            herd = existingHerd
        } else {
            guard try hasAnyHerdScopedRecords(in: context) else {
                // Do not mark the migration complete. An iCloud import can still deliver legacy
                // unscoped rows later in this launch; the next launch must be allowed to migrate them.
                return
            }
            herd = try defaultHerd(in: context)
        }

        var changed = false
        if shouldRunMigration {
            changed = try attachAllUnscopedRecords(in: context, to: herd)
        }

        try save(context, herd: herd, changed: changed)

        if shouldRunMigration {
            migrationState.set(currentMigrationVersion, forKey: migrationVersionKey)
        }
    }

    nonisolated static func existingDefaultHerd(in context: ModelContext) throws -> Herd? {
        var descriptor = FetchDescriptor<Herd>(
            sortBy: [SortDescriptor(\Herd.createdAt)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    nonisolated static func defaultHerd(in context: ModelContext) throws -> Herd {
        if let herd = try existingDefaultHerd(in: context) {
            return herd
        }

        let herd = Herd(name: defaultHerdName)
        context.insert(herd)
        return herd
    }

    private static func hasAnyHerdScopedRecords(in context: ModelContext) throws -> Bool {
        try hasAnyRecord(Animal.self, in: context)
            || hasAnyRecord(AnimalTag.self, in: context)
            || hasAnyRecord(AnimalStatusReference.self, in: context)
            || hasAnyRecord(StatusRecord.self, in: context)
            || hasAnyRecord(HealthRecord.self, in: context)
            || hasAnyRecord(PregnancyCheck.self, in: context)
            || hasAnyRecord(MovementRecord.self, in: context)
            || hasAnyRecord(Pasture.self, in: context)
            || hasAnyRecord(PastureGroup.self, in: context)
            || hasAnyRecord(TagColorDefinition.self, in: context)
            || hasAnyRecord(WorkingSession.self, in: context)
            || hasAnyRecord(WorkingQueueItem.self, in: context)
            || hasAnyRecord(WorkingTreatmentRecord.self, in: context)
            || hasAnyRecord(WorkingProtocolTemplate.self, in: context)
            || hasAnyRecord(FieldCheckSession.self, in: context)
            || hasAnyRecord(FieldCheckAnimalCheck.self, in: context)
            || hasAnyRecord(FieldCheckFinding.self, in: context)
    }

    private static func hasAnyRecord<Model: PersistentModel>(
        _ type: Model.Type,
        in context: ModelContext
    ) throws -> Bool {
        var descriptor = FetchDescriptor<Model>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
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
