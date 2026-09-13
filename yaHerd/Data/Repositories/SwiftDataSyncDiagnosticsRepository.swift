//
//  SwiftDataSyncDiagnosticsRepository.swift
//  yaHerd
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataSyncDiagnosticsRepository: SyncDiagnosticsRepository {
    let publicIDRepairService: (any PublicIDRepairService)?

    var storageInfo: SyncDiagnosticsStorageInfo? {
        SyncDiagnosticsStorageInfo(
            technologyName: "SwiftData",
            cloudKitContainerIdentifier: ModelContainerFactory.cloudKitContainerIdentifier,
            storeName: ModelContainerFactory.storeName,
            recoveryStoreName: ModelContainerFactory.recoveryStoreName
        )
    }

    private let context: ModelContext

    init(
        context: ModelContext,
        publicIDRepairService: (any PublicIDRepairService)? = nil
    ) {
        self.context = context
        if let publicIDRepairService {
            self.publicIDRepairService = BootstrapArtifactCleaningPublicIDRepairService(
                context: context,
                base: publicIDRepairService
            )
        } else {
            self.publicIDRepairService = nil
        }
    }

    func fetchCounts() throws -> SyncDiagnosticsCounts {
        SyncDiagnosticsCounts(
            herds: try count(Herd.self),
            animals: try count(Animal.self),
            pastures: try count(Pasture.self),
            pastureGroups: try count(PastureGroup.self),
            healthRecords: try count(HealthRecord.self),
            pregnancyChecks: try count(PregnancyCheck.self),
            movementRecords: try count(MovementRecord.self),
            statusRecords: try count(StatusRecord.self),
            workingSessions: try count(WorkingSession.self),
            workingQueueItems: try count(WorkingQueueItem.self),
            workingTreatmentRecords: try count(WorkingTreatmentRecord.self),
            fieldCheckSessions: try count(FieldCheckSession.self),
            fieldCheckAnimalChecks: try count(FieldCheckAnimalCheck.self),
            fieldCheckFindings: try count(FieldCheckFinding.self)
        )
    }

    func fetchAnimalIdentity(publicID: UUID) throws -> SyncDiagnosticsAnimalIdentity? {
        var descriptor = FetchDescriptor<Animal>(
            predicate: #Predicate { $0.publicID == publicID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.map(makeAnimalIdentity)
    }

    func fetchUniqueAnimalIdentity(tagNumber: String) throws -> SyncDiagnosticsAnimalIdentity? {
        var animalDescriptor = FetchDescriptor<Animal>(
            predicate: #Predicate { $0.tagNumber == tagNumber }
        )
        animalDescriptor.fetchLimit = 2
        let directMatches = try context.fetch(animalDescriptor)
        if directMatches.count == 1, let animal = directMatches.first {
            return makeAnimalIdentity(animal)
        }

        var tagDescriptor = FetchDescriptor<AnimalTag>(
            predicate: #Predicate { $0.number == tagNumber }
        )
        tagDescriptor.fetchLimit = 8
        let tagMatches = try context.fetch(tagDescriptor)
        let activePrimaryAnimals = tagMatches
            .filter { $0.isPrimary && $0.isActive }
            .compactMap(\.animal)
        let uniqueByPublicID = Dictionary(grouping: activePrimaryAnimals, by: \.publicID)
        guard uniqueByPublicID.count == 1,
              let animal = uniqueByPublicID.values.first?.first else {
            return nil
        }
        return makeAnimalIdentity(animal)
    }

    func fetchPublicIDRecord(
        entityType: PublicIDRepairEntityType,
        publicID: UUID
    ) throws -> SyncDiagnosticsPublicIDRecord? {
        switch entityType {
        case .movement:
            var descriptor = FetchDescriptor<MovementRecord>(
                predicate: #Predicate { $0.publicID == publicID }
            )
            descriptor.fetchLimit = 1
            guard let record = try context.fetch(descriptor).first else { return nil }
            return SyncDiagnosticsPublicIDRecord(
                entityType: entityType,
                animal: record.animal.map(makeAnimalIdentity),
                date: record.date,
                fromPasture: record.fromPasture,
                toPasture: record.toPasture
            )

        case .pregnancyCheck:
            var descriptor = FetchDescriptor<PregnancyCheck>(
                predicate: #Predicate { $0.publicID == publicID }
            )
            descriptor.fetchLimit = 1
            guard let record = try context.fetch(descriptor).first else { return nil }
            return SyncDiagnosticsPublicIDRecord(
                entityType: entityType,
                animal: record.animal.map(makeAnimalIdentity),
                date: record.date,
                resultRawValue: record.result.rawValue,
                estimatedDaysPregnant: record.estimatedDaysPregnant,
                dueDate: record.dueDate,
                technician: record.technician
            )

        case .statusRecord:
            var descriptor = FetchDescriptor<StatusRecord>(
                predicate: #Predicate { $0.publicID == publicID }
            )
            descriptor.fetchLimit = 1
            guard let record = try context.fetch(descriptor).first else { return nil }
            return SyncDiagnosticsPublicIDRecord(
                entityType: entityType,
                animal: record.animal.map(makeAnimalIdentity),
                date: record.date,
                oldStatusRawValue: record.oldStatus.rawValue,
                newStatusRawValue: record.newStatus.rawValue
            )

        default:
            return nil
        }
    }

    private func makeAnimalIdentity(_ animal: Animal) -> SyncDiagnosticsAnimalIdentity {
        var tagNumbers = Set<String>()

        let currentTag = animal.tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentTag.isEmpty {
            tagNumbers.insert(currentTag)
        }
        for tag in animal.tags {
            let normalized = tag.normalizedNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                tagNumbers.insert(normalized)
            }
        }

        return SyncDiagnosticsAnimalIdentity(
            summary: AnimalMapper.makeSummary(from: animal),
            tagNumbers: tagNumbers
        )
    }

    private func count<T: PersistentModel>(_ modelType: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }
}

/// Reinstalling while iCloud already contained data used to persist a fresh copy of every built-in
/// tag color before CloudKit imported the existing copies. SwiftData gives those copies different
/// physical CloudKit identities even though yaHerd's stable color UUID is the same. Public-ID
/// diagnostics then saw every animal/tag reference as ambiguous and asked the user to resolve the
/// same color hundreds of times.
///
/// A diagnostics scan is a safe place to collapse only that exact bootstrap artifact. A pending
/// durable repair transaction is never touched: the first scan is returned unchanged whenever
/// shared-data convergence is already in progress.
@MainActor
private final class BootstrapArtifactCleaningPublicIDRepairService: PublicIDRepairService {
    private let context: ModelContext
    private let base: any PublicIDRepairService

    init(
        context: ModelContext,
        base: any PublicIDRepairService
    ) {
        self.context = context
        self.base = base
    }

    func scan() async throws -> PublicIDRepairAssessment {
        let initialAssessment = try await base.scan()
        guard !initialAssessment.requiresBridgeConvergence else {
            return initialAssessment
        }

        let removedCount = try BuiltInTagColorDuplicateCleaner.removeSafeDuplicates(
            in: context
        )
        guard removedCount > 0 else {
            return initialAssessment
        }

        return try await base.scan()
    }

    func repair(
        resolutions: [PublicIDRepairReferenceResolution]
    ) async throws -> PublicIDRepairReport {
        try await base.repair(resolutions: resolutions)
    }
}

@MainActor
private enum BuiltInTagColorDuplicateCleaner {
    static func removeSafeDuplicates(in context: ModelContext) throws -> Int {
        let persisted = try context.fetch(FetchDescriptor<TagColorDefinition>())
        guard persisted.count > 1 else { return 0 }

        let builtInsByID = Dictionary(
            uniqueKeysWithValues: TagColorDefaults.seedDefaultColors().map { ($0.id, $0) }
        )
        let groups = Dictionary(grouping: persisted, by: \.id)
        var removedCount = 0

        for (id, group) in groups where group.count > 1 {
            guard let builtIn = builtInsByID[id] else { continue }

            let customized = group.filter { !matchesBuiltIn($0, builtIn) }
            // If more than one divergent customization exists, identity is genuinely ambiguous.
            // Leave that group to the normal backed-up public-ID repair workflow rather than guess.
            guard customized.count <= 1 else { continue }

            let keeper: TagColorDefinition
            if let customizedKeeper = customized.first {
                // Preserve an explicit user customization over any reinstall-created seed copies.
                keeper = customizedKeeper
            } else {
                // All copies are the same built-in value. Retain the oldest physical row because it
                // is the one most likely to belong to the original synchronized store.
                keeper = group.min(by: oldestFirst) ?? group[0]
            }

            for duplicate in group where duplicate !== keeper {
                context.delete(duplicate)
                removedCount += 1
            }
        }

        guard removedCount > 0 else { return 0 }
        try PersistenceLog.save(
            context,
            operation: "SwiftDataSyncDiagnosticsRepository.removeBootstrapTagColorDuplicates"
        )
        return removedCount
    }

    private static func matchesBuiltIn(
        _ persisted: TagColorDefinition,
        _ builtIn: TagColorSnapshot
    ) -> Bool {
        TagColorLibraryRules.normalizedNameKey(persisted.name)
            == TagColorLibraryRules.normalizedNameKey(builtIn.name)
            && persisted.prefix == TagColorLibraryRules.normalizedPrefix(
                builtIn.prefix,
                fallbackName: builtIn.name
            )
            && persisted.red == builtIn.rgba.r
            && persisted.green == builtIn.rgba.g
            && persisted.blue == builtIn.rgba.b
            && persisted.alpha == builtIn.rgba.a
            && persisted.sortOrder == builtIn.sortOrder
            && !persisted.isHidden
            && persisted.isDefault == builtIn.isDefault
    }

    private static func oldestFirst(
        _ lhs: TagColorDefinition,
        _ rhs: TagColorDefinition
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.updatedAt < rhs.updatedAt
    }
}
