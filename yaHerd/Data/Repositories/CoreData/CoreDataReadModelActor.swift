@preconcurrency import CoreData
import Foundation

enum CoreDataReadModelError: LocalizedError, Equatable, Sendable {
    case invalidHerdOwnership(
        entity: String,
        id: UUID,
        expectedHerdID: UUID,
        actualHerdID: UUID
    )
    case invalidSessionRelationship(
        entity: String,
        id: UUID,
        expectedSessionID: UUID,
        actualSessionID: UUID
    )
    case inconsistentOpenFindingCount(expected: Int, fetched: Int)

    var errorDescription: String? {
        switch self {
        case .invalidHerdOwnership:
            return "The read-model relationship belongs to another herd."
        case .invalidSessionRelationship:
            return "The read-model relationship points to another session."
        case .inconsistentOpenFindingCount:
            return "The Field Check Home read changed while its finding count was being resolved."
        }
    }
}

/// Async Core Data read-model boundary used by M9.
///
/// Each production dependency should receive its own actor instance so independent Home/Dashboard/
/// Animal-list reads do not serialize through one actor or one managed-object context.
actor CoreDataReadModelActor:
    HomeFieldCheckQueryReading,
    HomeWorkingQueryReading,
    AnimalListQueryReading
{
    private let contextFactory: CoreDataContextFactory
    private let lookup: CoreDataLookup
    private let currentHerdID: @MainActor @Sendable () -> UUID?

    init(
        assembly: CoreDataPersistenceAssembly,
        currentHerdID: @escaping @MainActor @Sendable () -> UUID?
    ) {
        self.contextFactory = assembly.contextFactory
        self.lookup = assembly.lookup
        self.currentHerdID = currentHerdID
    }

    func fetchAnimalSummaryPage(
        _ request: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup
        let requestedCount = request.limit + 1

        return try await context.perform {
            try Task.checkCancellation()
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            let untaggedCountRequest = NSFetchRequest<CDAnimal>(
                entityName: CDAnimal.coreDataEntityName
            )
            untaggedCountRequest.predicate = Self.untaggedAnimalPredicate(herd: herd)
            let untaggedCount = try context.count(for: untaggedCountRequest)

            var candidates: [CDAnimal] = []
            candidates.reserveCapacity(requestedCount)

            if request.offset < untaggedCount {
                let untaggedRequest = NSFetchRequest<CDAnimal>(
                    entityName: CDAnimal.coreDataEntityName
                )
                untaggedRequest.predicate = Self.untaggedAnimalPredicate(herd: herd)
                untaggedRequest.sortDescriptors = [
                    NSSortDescriptor(key: "name", ascending: true),
                    NSSortDescriptor(key: "id", ascending: true)
                ]
                untaggedRequest.fetchOffset = request.offset
                untaggedRequest.fetchLimit = requestedCount
                untaggedRequest.relationshipKeyPathsForPrefetching =
                    Self.animalSummaryPrefetchPaths

                candidates.append(contentsOf: try context.fetch(untaggedRequest))
            }

            if candidates.count < requestedCount {
                let taggedOffset = max(request.offset - untaggedCount, 0)
                let tagRequest = NSFetchRequest<CDAnimalTag>(
                    entityName: CDAnimalTag.coreDataEntityName
                )
                tagRequest.predicate = NSPredicate(
                    format: """
                    herd == %@ AND
                    animal.herd == %@ AND
                    isActive == YES AND
                    isPrimary == YES AND
                    number != ""
                    """,
                    herd,
                    herd
                )
                tagRequest.sortDescriptors = [
                    NSSortDescriptor(key: "number", ascending: true),
                    NSSortDescriptor(key: "animal.name", ascending: true),
                    NSSortDescriptor(key: "animal.id", ascending: true)
                ]
                tagRequest.fetchOffset = taggedOffset
                tagRequest.fetchLimit = requestedCount - candidates.count
                tagRequest.relationshipKeyPathsForPrefetching = [
                    "animal",
                    "animal.tags",
                    "animal.dam",
                    "animal.dam.tags",
                    "animal.currentPasture",
                    "animal.activeWorkingSession",
                    "animal.pregnancyChecks",
                    "animal.healthRecords"
                ]

                let tags = try context.fetch(tagRequest)
                for tag in tags {
                    guard tag.herd.id == herdID else {
                        throw CoreDataReadModelError.invalidHerdOwnership(
                            entity: CDAnimalTag.coreDataEntityName,
                            id: tag.id,
                            expectedHerdID: herdID,
                            actualHerdID: tag.herd.id
                        )
                    }
                    guard tag.animal.herd.id == herdID else {
                        throw CoreDataReadModelError.invalidHerdOwnership(
                            entity: CDAnimal.coreDataEntityName,
                            id: tag.animal.id,
                            expectedHerdID: herdID,
                            actualHerdID: tag.animal.herd.id
                        )
                    }
                    candidates.append(tag.animal)
                }
            }

            var seenAnimalIDs = Set<UUID>()
            for animal in candidates {
                guard seenAnimalIDs.insert(animal.id).inserted else {
                    throw CoreDataPersistenceError.duplicateApplicationID(
                        entity: CDAnimal.coreDataEntityName,
                        id: animal.id,
                        herdID: herdID
                    )
                }
            }

            let hasMore = candidates.count > request.limit
            return AnimalSummaryPage(
                animals: try candidates.prefix(request.limit).map {
                    try CoreDataAnimalProjection.summary($0)
                },
                hasMore: hasMore
            )
        }
    }

    func fetchAnimalPastureOptions(
        limit: Int
    ) async throws -> [PastureOption] {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup
        let pageSize = Self.normalizedLimit(limit)

        return try await context.perform {
            try Task.checkCancellation()
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            var offset = 0
            var options: [PastureOption] = []
            var seenIDs = Set<UUID>()

            while true {
                try Task.checkCancellation()

                let request = NSFetchRequest<CDPasture>(
                    entityName: CDPasture.coreDataEntityName
                )
                request.predicate = NSPredicate(format: "herd == %@", herd)
                request.sortDescriptors = [
                    NSSortDescriptor(key: "name", ascending: true),
                    NSSortDescriptor(key: "sortOrder", ascending: true),
                    NSSortDescriptor(key: "id", ascending: true)
                ]
                request.fetchOffset = offset
                request.fetchLimit = pageSize

                let pastures = try context.fetch(request)
                for pasture in pastures {
                    guard pasture.herd.id == herdID else {
                        throw CoreDataReadModelError.invalidHerdOwnership(
                            entity: CDPasture.coreDataEntityName,
                            id: pasture.id,
                            expectedHerdID: herdID,
                            actualHerdID: pasture.herd.id
                        )
                    }
                    guard seenIDs.insert(pasture.id).inserted else {
                        throw CoreDataPersistenceError.duplicateApplicationID(
                            entity: CDPasture.coreDataEntityName,
                            id: pasture.id,
                            herdID: herdID
                        )
                    }
                    options.append(
                        PastureOption(
                            id: pasture.id,
                            name: pasture.name
                        )
                    )
                }

                guard pastures.count == pageSize else {
                    return options
                }
                offset += pastures.count
            }
        }
    }

    func fetchHomeFieldCheckRecords() async throws -> HomeFieldCheckRecords {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup

        return try await context.perform {
            try Task.checkCancellation()
            try context.setQueryGenerationFrom(.current)
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            try Self.validateUnresolvedFindingAggregationGraph(
                herd: herd,
                herdID: herdID,
                in: context
            )

            let sessionRequest = NSFetchRequest<CDFieldCheckSession>(
                entityName: CDFieldCheckSession.coreDataEntityName
            )
            sessionRequest.predicate = NSPredicate(
                format: """
                herd == %@ AND (
                    completedAt == nil OR
                    SUBQUERY(animalChecks, $check, $check.missingConfirmedAt != nil).@count > 0 OR
                    SUBQUERY(findings, $finding, $finding.statusRawValue IN %@).@count > 0
                )
                """,
                herd,
                Self.unresolvedFindingStatusRawValues
            )
            sessionRequest.sortDescriptors = [
                NSSortDescriptor(key: "startedAt", ascending: false),
                NSSortDescriptor(key: "id", ascending: true)
            ]
            sessionRequest.relationshipKeyPathsForPrefetching = [
                "animalChecks",
                "findings"
            ]

            let warningSessions = try context.fetch(sessionRequest)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                warningSessions,
                herdID: herdID
            )
            try Self.validateFieldCheckWarningGraph(
                warningSessions,
                herdID: herdID
            )

            let findingRequest = NSFetchRequest<CDFieldCheckFinding>(
                entityName: CDFieldCheckFinding.coreDataEntityName
            )
            findingRequest.predicate = NSPredicate(
                format: "herd == %@ AND session.herd == %@ AND statusRawValue IN %@",
                herd,
                herd,
                Self.unresolvedFindingStatusRawValues
            )
            let openFindingCount = try context.count(for: findingRequest)

            let openFindings: [FieldCheckFindingSnapshot]
            if openFindingCount == 1 {
                findingRequest.fetchLimit = 1
                findingRequest.sortDescriptors = [
                    NSSortDescriptor(key: "recordedAt", ascending: false),
                    NSSortDescriptor(key: "id", ascending: true)
                ]
                let fetchedFindings = try context.fetch(findingRequest)
                guard let finding = fetchedFindings.first else {
                    throw CoreDataReadModelError.inconsistentOpenFindingCount(
                        expected: 1,
                        fetched: fetchedFindings.count
                    )
                }
                try Self.validateFindingRelationship(
                    finding,
                    herdID: herdID
                )
                openFindings = [
                    try FieldCheckMapper.makeFindingSnapshot(from: finding)
                ]
            } else {
                openFindings = []
            }

            let historyRequest = NSFetchRequest<CDFieldCheckSession>(
                entityName: CDFieldCheckSession.coreDataEntityName
            )
            historyRequest.predicate = NSPredicate(format: "herd == %@", herd)
            historyRequest.fetchLimit = 1
            let hasHistory = try context.count(for: historyRequest) > 0

            return HomeFieldCheckRecords(
                sessions: try warningSessions.map {
                    try FieldCheckMapper.makeSessionSummary(from: $0)
                },
                openFindings: openFindings,
                openFindingCount: openFindingCount,
                hasHistory: hasHistory
            )
        }
    }

    func fetchHomeTreatmentTemplates(
        limit: Int
    ) async throws -> [WorkingTreatmentTemplateSummary] {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup
        let fetchLimit = Self.normalizedLimit(limit)

        return try await context.perform {
            try Task.checkCancellation()
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            let request = NSFetchRequest<CDWorkingTreatmentTemplate>(
                entityName: CDWorkingTreatmentTemplate.coreDataEntityName
            )
            request.predicate = NSPredicate(format: "herd == %@", herd)
            request.sortDescriptors = [
                NSSortDescriptor(key: "name", ascending: true),
                NSSortDescriptor(key: "id", ascending: true)
            ]
            request.fetchLimit = fetchLimit

            let templates = try context.fetch(request)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                templates,
                herdID: herdID
            )

            return try templates.map { template in
                let items = try JSONDecoder().decode(
                    [WorkingTreatmentPlanItem].self,
                    from: template.itemsData
                )
                return WorkingTreatmentTemplateSummary(
                    id: template.id,
                    name: template.name,
                    treatmentCount: items.count
                )
            }
        }
    }

    private func selectedHerdID() async throws -> UUID {
        guard let herdID = await currentHerdID() else {
            throw HerdRepositoryError.missingHerd
        }
        return herdID
    }

    private static func normalizedLimit(_ requestedLimit: Int) -> Int {
        min(max(requestedLimit, 1), ReadPageRequest.maximumLimit)
    }

    private static let animalSummaryPrefetchPaths = [
        "tags",
        "dam",
        "dam.tags",
        "currentPasture",
        "activeWorkingSession",
        "pregnancyChecks",
        "healthRecords"
    ]

    private static func untaggedAnimalPredicate(
        herd: CDHerd
    ) -> NSPredicate {
        NSPredicate(
            format: """
            herd == %@ AND
            SUBQUERY(
                tags,
                $tag,
                $tag.isActive == YES AND
                $tag.isPrimary == YES AND
                $tag.number != ""
            ).@count == 0
            """,
            herd
        )
    }

    private static let unresolvedFindingStatusRawValues = [
        FieldCheckFindingStatus.open.rawValue,
        FieldCheckFindingStatus.monitoring.rawValue
    ]

    private static let validFindingStatusRawValues = FieldCheckFindingStatus.allCases.map(\.rawValue)

    private static func validateUnresolvedFindingAggregationGraph(
        herd: CDHerd,
        herdID: UUID,
        in context: NSManagedObjectContext
    ) throws {
        let corruptRequest = NSFetchRequest<CDFieldCheckFinding>(
            entityName: CDFieldCheckFinding.coreDataEntityName
        )
        corruptRequest.predicate = NSPredicate(
            format: """
            herd == %@ AND (
                session.herd != %@ OR
                NOT (statusRawValue IN %@)
            )
            """,
            herd,
            herd,
            validFindingStatusRawValues
        )
        corruptRequest.fetchLimit = 1
        corruptRequest.relationshipKeyPathsForPrefetching = ["session"]

        if let finding = try context.fetch(corruptRequest).first {
            try validateFindingRelationship(
                finding,
                herdID: herdID
            )
            _ = try FieldCheckMapper.makeFindingSnapshot(from: finding)
        }

        let idRequest = NSFetchRequest<NSDictionary>(
            entityName: CDFieldCheckFinding.coreDataEntityName
        )
        idRequest.resultType = .dictionaryResultType
        idRequest.propertiesToFetch = ["id"]
        idRequest.predicate = NSPredicate(
            format: "herd == %@ AND session.herd == %@ AND statusRawValue IN %@",
            herd,
            herd,
            unresolvedFindingStatusRawValues
        )

        var seenIDs = Set<UUID>()
        for row in try context.fetch(idRequest) {
            let id: UUID?
            if let value = row["id"] as? UUID {
                id = value
            } else if let value = row["id"] as? NSUUID {
                id = value as UUID
            } else {
                id = nil
            }
            guard let id else {
                continue
            }
            guard seenIDs.insert(id).inserted else {
                throw CoreDataPersistenceError.duplicateApplicationID(
                    entity: CDFieldCheckFinding.coreDataEntityName,
                    id: id,
                    herdID: herdID
                )
            }
        }
    }

    private static func validateFieldCheckWarningGraph(
        _ sessions: [CDFieldCheckSession],
        herdID: UUID
    ) throws {
        let allChecks = sessions.flatMap {
            ($0.animalChecks?.allObjects as? [CDFieldCheckAnimalCheck]) ?? []
        }
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            allChecks,
            herdID: herdID
        )

        for session in sessions {
            guard session.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDFieldCheckSession.coreDataEntityName,
                    id: session.id,
                    expectedHerdID: herdID,
                    actualHerdID: session.herd.id
                )
            }

            let checks = (session.animalChecks?.allObjects as? [CDFieldCheckAnimalCheck]) ?? []
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                checks,
                herdID: herdID
            )
            for check in checks {
                guard check.herd.id == herdID else {
                    throw CoreDataReadModelError.invalidHerdOwnership(
                        entity: CDFieldCheckAnimalCheck.coreDataEntityName,
                        id: check.id,
                        expectedHerdID: herdID,
                        actualHerdID: check.herd.id
                    )
                }
                guard check.session.objectID == session.objectID else {
                    throw CoreDataReadModelError.invalidSessionRelationship(
                        entity: CDFieldCheckAnimalCheck.coreDataEntityName,
                        id: check.id,
                        expectedSessionID: session.id,
                        actualSessionID: check.session.id
                    )
                }
            }

            let findings = (session.findings?.allObjects as? [CDFieldCheckFinding]) ?? []
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                findings,
                herdID: herdID
            )
            for finding in findings {
                try validateFindingRelationship(
                    finding,
                    expectedSession: session,
                    herdID: herdID
                )
            }
        }
    }

    private static func validateFindingRelationship(
        _ finding: CDFieldCheckFinding,
        expectedSession: CDFieldCheckSession? = nil,
        herdID: UUID
    ) throws {
        guard finding.herd.id == herdID else {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDFieldCheckFinding.coreDataEntityName,
                id: finding.id,
                expectedHerdID: herdID,
                actualHerdID: finding.herd.id
            )
        }
        guard finding.session.herd.id == herdID else {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDFieldCheckSession.coreDataEntityName,
                id: finding.session.id,
                expectedHerdID: herdID,
                actualHerdID: finding.session.herd.id
            )
        }
        if let expectedSession,
           finding.session.objectID != expectedSession.objectID {
            throw CoreDataReadModelError.invalidSessionRelationship(
                entity: CDFieldCheckFinding.coreDataEntityName,
                id: finding.id,
                expectedSessionID: expectedSession.id,
                actualSessionID: finding.session.id
            )
        }
    }
}
