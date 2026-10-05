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
    DashboardQueryReading,
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

    func fetchDashboardRecords() async throws -> DashboardRecords {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup

        return try await context.perform {
            try Task.checkCancellation()
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            let animalRequest = NSFetchRequest<CDAnimal>(
                entityName: CDAnimal.coreDataEntityName
            )
            animalRequest.predicate = NSPredicate(format: "herd == %@", herd)
            animalRequest.relationshipKeyPathsForPrefetching =
                Self.dashboardAnimalPrefetchPaths
            let animals = try context.fetch(animalRequest)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                animals,
                herdID: herdID
            )

            let pastureRecords = try Self.dashboardPastureRecords(
                herd: herd,
                herdID: herdID,
                context: context
            )

            let workingRequest = NSFetchRequest<CDWorkingSession>(
                entityName: CDWorkingSession.coreDataEntityName
            )
            workingRequest.predicate = NSPredicate(
                format: "herd == %@ AND statusRawValue == %@",
                herd,
                WorkingSessionStatus.active.rawValue
            )
            workingRequest.sortDescriptors = [
                NSSortDescriptor(key: "date", ascending: false),
                NSSortDescriptor(key: "id", ascending: true)
            ]
            workingRequest.fetchLimit = 25
            workingRequest.relationshipKeyPathsForPrefetching = [
                "queueItems",
                "sourcePasture"
            ]
            let sessions = try context.fetch(workingRequest)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                sessions,
                herdID: herdID
            )

            return DashboardRecords(
                animals: try Self.dashboardAnimalRecords(
                    animals,
                    herdID: herdID
                ),
                pastures: pastureRecords,
                workingSessions: try sessions.map {
                    try Self.dashboardWorkingSessionRecord(
                        $0,
                        herdID: herdID
                    )
                }
            )
        }
    }

    func fetchDashboardAnimalRecords(
        kind: DashboardAnimalListKind
    ) async throws -> [DashboardAnimalRecord] {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup

        return try await context.perform {
            try Task.checkCancellation()
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            let request = NSFetchRequest<CDAnimal>(
                entityName: CDAnimal.coreDataEntityName
            )
            request.predicate = Self.dashboardAnimalPredicate(
                kind: kind,
                herd: herd
            )
            request.relationshipKeyPathsForPrefetching =
                Self.dashboardAnimalPrefetchPaths

            let animals = try context.fetch(request)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                animals,
                herdID: herdID
            )
            return try Self.dashboardAnimalRecords(
                animals,
                herdID: herdID
            )
        }
    }

    func fetchDashboardPastureRecords() async throws -> [DashboardPastureRecord] {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup

        return try await context.perform {
            try Task.checkCancellation()
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return try Self.dashboardPastureRecords(
                herd: herd,
                herdID: herdID,
                context: context
            )
        }
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

    private static let dashboardAnimalPrefetchPaths = [
        "tags",
        "dam",
        "dam.tags",
        "currentPasture",
        "activeWorkingSession",
        "pregnancyChecks",
        "healthRecords",
        "damOffspring",
        "movementRecords",
        "statusRecords"
    ]

    private static func dashboardAnimalPredicate(
        kind: DashboardAnimalListKind,
        herd: CDHerd
    ) -> NSPredicate {
        let active = NSPredicate(
            format: "herd == %@ AND isArchived == NO AND statusRawValue == %@",
            herd,
            AnimalStatus.active.rawValue
        )
        switch kind {
        case .active:
            return active
        case .workingPen:
            return NSCompoundPredicate(
                andPredicateWithSubpredicates: [
                    active,
                    NSPredicate(format: "activeWorkingSession != nil")
                ]
            )
        case .unassigned:
            return NSCompoundPredicate(
                andPredicateWithSubpredicates: [
                    active,
                    NSPredicate(format: "activeWorkingSession == nil"),
                    NSPredicate(format: "currentPasture == nil")
                ]
            )
        }
    }

    private static func dashboardAnimalRecords(
        _ animals: [CDAnimal],
        herdID: UUID
    ) throws -> [DashboardAnimalRecord] {
        try animals.map { animal -> (CDAnimal, DashboardAnimalRecord) in
            try validateDashboardAnimalRelationships(
                animal,
                herdID: herdID
            )
            return (
                animal,
                try dashboardAnimalRecord(animal)
            )
        }
        .sorted { lhs, rhs in
            let tagOrder = lhs.1.displayTagNumber.localizedStandardCompare(
                rhs.1.displayTagNumber
            )
            if tagOrder != .orderedSame {
                return tagOrder == .orderedAscending
            }
            let nameOrder = lhs.0.name.localizedStandardCompare(rhs.0.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }
        .map { $0.1 }
    }

    private static func dashboardAnimalRecord(
        _ animal: CDAnimal
    ) throws -> DashboardAnimalRecord {
        let summary = try CoreDataAnimalProjection.summary(animal)
        let healthRecords = CoreDataAnimalProjection.managedHealthRecords(animal)

        return DashboardAnimalRecord(
            id: summary.id,
            displayTagNumber: summary.displayTagNumber,
            displayTagColorID: summary.displayTagColorID,
            damID: animal.dam?.id,
            damDisplayTagNumber: summary.damDisplayTagNumber,
            damDisplayTagColorID: summary.damDisplayTagColorID,
            sex: summary.sex,
            animalType: summary.animalType,
            status: summary.status,
            isArchived: summary.isArchived,
            pastureID: summary.pastureID,
            pastureName: summary.pastureName,
            location: summary.location,
            lastPregnancyCheckDate: summary.lastPregnancyCheckDate,
            lastPregnancyStatus: dashboardPregnancyStatus(
                summary.lastPregnancyStatus
            ),
            expectedCalvingDate: summary.expectedCalvingDate,
            lastTreatmentDate: summary.lastTreatmentDate,
            birthDate: summary.birthDate,
            saleDate: animal.saleDate,
            deathDate: animal.deathDate,
            healthRecords: healthRecords.map {
                DashboardHealthRecord(
                    date: $0.date,
                    treatment: $0.treatment,
                    notes: $0.notes
                )
            },
            offspringCount: CoreDataAnimalProjection
                .managedMaternalOffspring(animal)
                .count
        )
    }

    private static func dashboardPregnancyStatus(
        _ status: AnimalPregnancyStatus?
    ) -> DashboardPregnancyStatus? {
        guard let status else { return nil }
        switch status {
        case .open:
            return .open
        case .pregnant:
            return .pregnant
        case .unknown:
            return .unknown
        }
    }

    private static func dashboardPastureRecords(
        herd: CDHerd,
        herdID: UUID,
        context: NSManagedObjectContext
    ) throws -> [DashboardPastureRecord] {
        let request = NSFetchRequest<CDPasture>(
            entityName: CDPasture.coreDataEntityName
        )
        request.predicate = NSPredicate(format: "herd == %@", herd)
        request.sortDescriptors = [
            NSSortDescriptor(key: "name", ascending: true),
            NSSortDescriptor(key: "id", ascending: true)
        ]
        request.relationshipKeyPathsForPrefetching = ["group"]

        let pastures = try context.fetch(request)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            pastures,
            herdID: herdID
        )

        return try pastures.map { pasture in
            guard pasture.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDPasture.coreDataEntityName,
                    id: pasture.id,
                    expectedHerdID: herdID,
                    actualHerdID: pasture.herd.id
                )
            }
            if let group = pasture.group,
               group.herd.id != herdID {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDPastureGroup.coreDataEntityName,
                    id: group.id,
                    expectedHerdID: herdID,
                    actualHerdID: group.herd.id
                )
            }

            let countRequest = NSFetchRequest<CDAnimal>(
                entityName: CDAnimal.coreDataEntityName
            )
            countRequest.predicate = NSPredicate(
                format: """
                herd == %@ AND
                currentPasture == %@ AND
                isArchived == NO AND
                statusRawValue == %@
                """,
                herd,
                pasture,
                AnimalStatus.active.rawValue
            )
            let activeAnimalCount = try context.count(for: countRequest)

            return DashboardPastureRecord(
                id: pasture.id,
                name: pasture.name,
                acreage: pasture.acreage?.doubleValue,
                usableAcreage: pasture.usableAcreage?.doubleValue,
                targetAcresPerHead: pasture.targetAcresPerHead?.doubleValue,
                activeAnimalCount: activeAnimalCount,
                lastGrazedDate: pasture.lastGrazedDate,
                restDays: pasture.group.map { Int($0.restDays) }
            )
        }
    }

    private static func dashboardWorkingSessionRecord(
        _ session: CDWorkingSession,
        herdID: UUID
    ) throws -> DashboardWorkingSessionRecord {
        guard session.herd.id == herdID else {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDWorkingSession.coreDataEntityName,
                id: session.id,
                expectedHerdID: herdID,
                actualHerdID: session.herd.id
            )
        }
        if let sourcePasture = session.sourcePasture,
           sourcePasture.herd.id != herdID {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDPasture.coreDataEntityName,
                id: sourcePasture.id,
                expectedHerdID: herdID,
                actualHerdID: sourcePasture.herd.id
            )
        }

        let queueItems = (session.queueItems?.allObjects as? [CDWorkingQueueItem]) ?? []
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            queueItems,
            herdID: herdID
        )
        for item in queueItems {
            guard item.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDWorkingQueueItem.coreDataEntityName,
                    id: item.id,
                    expectedHerdID: herdID,
                    actualHerdID: item.herd.id
                )
            }
            guard item.session.objectID == session.objectID else {
                throw CoreDataReadModelError.invalidSessionRelationship(
                    entity: CDWorkingQueueItem.coreDataEntityName,
                    id: item.id,
                    expectedSessionID: session.id,
                    actualSessionID: item.session.id
                )
            }
        }

        let summary = try WorkingMapper.makeSessionSummary(from: session)
        return DashboardWorkingSessionRecord(
            id: summary.id,
            date: summary.date,
            isActive: summary.status == .active,
            sourcePastureName: summary.sourcePastureName,
            treatmentTemplateName: summary.treatmentTemplateName,
            totalQueueItems: summary.totalQueueItems,
            completedQueueItems: summary.completedQueueItems
        )
    }

    private static func validateDashboardAnimalRelationships(
        _ animal: CDAnimal,
        herdID: UUID
    ) throws {
        guard animal.herd.id == herdID else {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDAnimal.coreDataEntityName,
                id: animal.id,
                expectedHerdID: herdID,
                actualHerdID: animal.herd.id
            )
        }
        if let pasture = animal.currentPasture,
           pasture.herd.id != herdID {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDPasture.coreDataEntityName,
                id: pasture.id,
                expectedHerdID: herdID,
                actualHerdID: pasture.herd.id
            )
        }
        if let session = animal.activeWorkingSession,
           session.herd.id != herdID {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDWorkingSession.coreDataEntityName,
                id: session.id,
                expectedHerdID: herdID,
                actualHerdID: session.herd.id
            )
        }
        if let dam = animal.dam,
           dam.herd.id != herdID {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDAnimal.coreDataEntityName,
                id: dam.id,
                expectedHerdID: herdID,
                actualHerdID: dam.herd.id
            )
        }

        for tag in CoreDataAnimalProjection.managedTags(animal) {
            guard tag.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDAnimalTag.coreDataEntityName,
                    id: tag.id,
                    expectedHerdID: herdID,
                    actualHerdID: tag.herd.id
                )
            }
            if let color = tag.color,
               color.herd.id != herdID {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDTagColorDefinition.coreDataEntityName,
                    id: color.id,
                    expectedHerdID: herdID,
                    actualHerdID: color.herd.id
                )
            }
        }
        for record in CoreDataAnimalProjection.managedHealthRecords(animal) {
            guard record.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDHealthRecord.coreDataEntityName,
                    id: record.id,
                    expectedHerdID: herdID,
                    actualHerdID: record.herd.id
                )
            }
        }
        for check in CoreDataAnimalProjection.managedPregnancyChecks(animal) {
            guard check.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDPregnancyCheck.coreDataEntityName,
                    id: check.id,
                    expectedHerdID: herdID,
                    actualHerdID: check.herd.id
                )
            }
        }
        for offspring in CoreDataAnimalProjection.managedMaternalOffspring(animal) {
            guard offspring.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDAnimal.coreDataEntityName,
                    id: offspring.id,
                    expectedHerdID: herdID,
                    actualHerdID: offspring.herd.id
                )
            }
        }
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
