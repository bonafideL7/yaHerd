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
    case inconsistentAnimalPage(expected: Int, fetched: Int)
    case invalidActivePrimaryTagCardinality(
        animalID: UUID,
        activeTagCount: Int,
        primaryTagCount: Int
    )

    var errorDescription: String? {
        switch self {
        case .invalidHerdOwnership:
            return "The read-model relationship belongs to another herd."
        case .invalidSessionRelationship:
            return "The read-model relationship points to another session."
        case .inconsistentOpenFindingCount:
            return "The Field Check Home read changed while its finding count was being resolved."
        case .inconsistentAnimalPage:
            return "The Animal-list read changed while its page was being resolved."
        case .invalidActivePrimaryTagCardinality:
            return "The read-model Animal tag graph has an invalid active primary-tag state."
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
    AnimalListQueryReading,
    AnimalListFilteredQueryReading,
    AnimalReferenceQueryReading
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
        try await fetchAnimalSummaryPage(
            matching: nil,
            page: request
        )
    }

    func fetchAnimalSummaryPage(
        matching query: AnimalListFilterQuery,
        page: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        try await fetchAnimalSummaryPage(
            matching: Optional(query),
            page: page
        )
    }

    private func fetchAnimalSummaryPage(
        matching query: AnimalListFilterQuery?,
        page: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup
        let requestedCount = page.limit + 1
        let referenceDate = Date()
        let calendar = Calendar.current

        return try await context.perform {
            try Task.checkCancellation()
            try context.setQueryGenerationFrom(.current)
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            try Self.validateAnimalApplicationIDs(
                herd: herd,
                herdID: herdID,
                in: context
            )
            try Self.validateAnimalListTagIntegrity(
                herd: herd,
                herdID: herdID,
                in: context
            )
            try Self.validateAnimalListQueryIntegrity(
                query: query,
                herd: herd,
                herdID: herdID,
                in: context
            )

            let sortOrder = query?.sortOrder ?? .tagAscending
            let candidates = try Self.fetchLightweightSortedQueryCandidates(
                query: query,
                sortOrder: sortOrder,
                herd: herd,
                herdID: herdID,
                referenceDate: referenceDate,
                calendar: calendar,
                offset: page.offset,
                limit: requestedCount,
                in: context
            )

            let hydratedCandidates = try Self.hydrateAnimalSummaryCandidates(
                candidates,
                herd: herd,
                in: context
            )

            var candidateIDs = Set<UUID>()
            for animal in hydratedCandidates {
                guard candidateIDs.insert(animal.id).inserted else {
                    throw CoreDataPersistenceError.duplicateApplicationID(
                        entity: CDAnimal.coreDataEntityName,
                        id: animal.id,
                        herdID: herdID
                    )
                }
                try Self.validateAnimalReadRelationships(
                    animal,
                    herdID: herdID
                )
            }

            let hasMore = hydratedCandidates.count > page.limit
            return AnimalSummaryPage(
                animals: try hydratedCandidates.prefix(page.limit).map {
                    try CoreDataAnimalProjection.summary(
                        $0,
                        now: referenceDate,
                        calendar: calendar
                    )
                },
                hasMore: hasMore
            )
        }
    }

    func fetchAnimalReferencePage(
        matching query: AnimalReferenceQuery,
        page: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup
        let requestedCount = page.limit + 1
        let referenceDate = Date()
        let calendar = Calendar.current

        return try await context.perform {
            try Task.checkCancellation()
            try context.setQueryGenerationFrom(.current)
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            try Self.validateAnimalApplicationIDs(
                herd: herd,
                herdID: herdID,
                in: context
            )
            try Self.validateAnimalListTagIntegrity(
                herd: herd,
                herdID: herdID,
                in: context
            )
            try Self.validateAnimalListQueryIntegrity(
                query: nil,
                herd: herd,
                herdID: herdID,
                in: context
            )

            let candidates = try Self.fetchAnimalReferenceCandidates(
                query: query,
                herd: herd,
                offset: page.offset,
                limit: requestedCount,
                in: context
            )
            let hydratedCandidates = try Self.hydrateAnimalSummaryCandidates(
                candidates,
                herd: herd,
                in: context
            )

            for animal in hydratedCandidates {
                try Self.validateAnimalReadRelationships(
                    animal,
                    herdID: herdID
                )
            }

            let hasMore = hydratedCandidates.count > page.limit
            return AnimalSummaryPage(
                animals: try hydratedCandidates.prefix(page.limit).map {
                    try CoreDataAnimalProjection.summary(
                        $0,
                        now: referenceDate,
                        calendar: calendar
                    )
                },
                hasMore: hasMore
            )
        }
    }

    func containsAnimal(id: UUID) async throws -> Bool {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup

        return try await context.perform {
            try Task.checkCancellation()
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            let request = NSFetchRequest<NSDictionary>(
                entityName: CDAnimal.coreDataEntityName
            )
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["id"]
            request.predicate = NSPredicate(
                format: "herd == %@ AND id == %@",
                herd,
                id as NSUUID
            )
            request.fetchLimit = 2

            let rows = try context.fetch(request)
            guard rows.count <= 1 else {
                throw CoreDataPersistenceError.duplicateApplicationID(
                    entity: CDAnimal.coreDataEntityName,
                    id: id,
                    herdID: herdID
                )
            }
            return !rows.isEmpty
        }
    }

    private static let animalLightweightScanBatchSize = 250

    private struct AnimalListQueryCandidate {
        let animal: CDAnimal
        let animalType: AnimalType?
        let sex: Sex
        let status: AnimalStatus
        let displayTagNumber: String
        let pastureSortKey: String
    }

    private struct AnimalReferenceCandidate {
        let animal: CDAnimal
        let displayTagNumber: String
    }

    private static func fetchAnimalReferenceCandidates(
        query: AnimalReferenceQuery,
        herd: CDHerd,
        offset: Int,
        limit: Int,
        in context: NSManagedObjectContext
    ) throws -> [CDAnimal] {
        let predicate = animalReferencePredicate(
            query: query,
            herd: herd
        )
        var sourceOffset = 0
        var candidates: [AnimalReferenceCandidate] = []

        while true {
            try Task.checkCancellation()
            let request = NSFetchRequest<CDAnimal>(
                entityName: CDAnimal.coreDataEntityName
            )
            request.predicate = predicate
            request.sortDescriptors = [
                NSSortDescriptor(key: "id", ascending: true)
            ]
            request.fetchOffset = sourceOffset
            request.fetchLimit = animalLightweightScanBatchSize
            request.relationshipKeyPathsForPrefetching = ["tags"]

            let batch = try context.fetch(request)
            if batch.isEmpty {
                break
            }

            candidates.append(
                contentsOf: batch.map {
                    AnimalReferenceCandidate(
                        animal: $0,
                        displayTagNumber: CoreDataAnimalProjection
                            .primaryTagFields(
                                CoreDataAnimalProjection.managedTags($0)
                            )
                            .number
                    )
                }
            )

            sourceOffset += batch.count
            if batch.count < animalLightweightScanBatchSize {
                break
            }
        }

        candidates.sort {
            animalReferenceCandidatePrecedes(
                $0,
                $1,
                sortOrder: query.sortOrder
            )
        }

        return Array(
            candidates
                .dropFirst(offset)
                .prefix(limit)
                .map(\.animal)
        )
    }

    private static func animalReferenceCandidatePrecedes(
        _ lhs: AnimalReferenceCandidate,
        _ rhs: AnimalReferenceCandidate,
        sortOrder: AnimalReferenceSortOrder
    ) -> Bool {
        let lhsKey: String
        let rhsKey: String

        switch sortOrder {
        case .displayTag:
            lhsKey = lhs.displayTagNumber
            rhsKey = rhs.displayTagNumber
        case .displayTagOrName:
            lhsKey = lhs.displayTagNumber.isEmpty
                ? lhs.animal.name
                : lhs.displayTagNumber
            rhsKey = rhs.displayTagNumber.isEmpty
                ? rhs.animal.name
                : rhs.displayTagNumber
        }

        let keyOrder = lhsKey.localizedStandardCompare(rhsKey)
        if keyOrder != .orderedSame {
            return keyOrder == .orderedAscending
        }

        let nameOrder = lhs.animal.name.localizedStandardCompare(
            rhs.animal.name
        )
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.animal.id.uuidString < rhs.animal.id.uuidString
    }

    private static func fetchLightweightSortedQueryCandidates(
        query: AnimalListFilterQuery?,
        sortOrder: AnimalListQuerySortOrder,
        herd: CDHerd,
        herdID: UUID,
        referenceDate: Date,
        calendar: Calendar,
        offset: Int,
        limit: Int,
        in context: NSManagedObjectContext
    ) throws -> [CDAnimal] {
        let predicate = animalListPredicate(
            query: query,
            herd: herd
        )
        let needsAnimalType =
            query?.animalType != nil || sortOrder == .animalType
        var prefetchPaths = ["tags"]
        if sortOrder == .pasture {
            prefetchPaths.append(contentsOf: [
                "currentPasture",
                "activeWorkingSession"
            ])
        }
        if needsAnimalType {
            prefetchPaths.append(contentsOf: [
                "healthRecords",
                "damOffspring"
            ])
        }

        var sourceOffset = 0
        var candidates: [AnimalListQueryCandidate] = []

        while true {
            try Task.checkCancellation()
            let request = NSFetchRequest<CDAnimal>(
                entityName: CDAnimal.coreDataEntityName
            )
            request.predicate = predicate
            request.sortDescriptors = [
                NSSortDescriptor(key: "id", ascending: true)
            ]
            request.fetchOffset = sourceOffset
            request.fetchLimit = animalLightweightScanBatchSize
            request.relationshipKeyPathsForPrefetching = prefetchPaths

            let batch = try context.fetch(request)
            if batch.isEmpty {
                break
            }

            for animal in batch {
                let type: AnimalType?
                if needsAnimalType {
                    try validateAnimalTypeRelationships(
                        animal,
                        herdID: herdID
                    )
                    type = try CoreDataAnimalProjection.animalType(
                        animal,
                        now: referenceDate,
                        calendar: calendar
                    )
                } else {
                    type = nil
                }

                if let selectedType = query?.animalType,
                   type != selectedType {
                    continue
                }

                candidates.append(
                    AnimalListQueryCandidate(
                        animal: animal,
                        animalType: type,
                        sex: try CoreDataAnimalProjection.sex(animal),
                        status: try CoreDataAnimalProjection.status(animal),
                        displayTagNumber: animalListDisplayTagNumber(animal),
                        pastureSortKey: sortOrder == .pasture
                            ? animalListPastureSortKey(animal)
                            : ""
                    )
                )
            }

            sourceOffset += batch.count
            if batch.count < animalLightweightScanBatchSize {
                break
            }
        }

        candidates.sort { lhs, rhs in
            animalListQueryCandidatePrecedes(
                lhs,
                rhs,
                sortOrder: sortOrder
            )
        }

        return Array(
            candidates
                .dropFirst(offset)
                .prefix(limit)
                .map(\.animal)
        )
    }

    private static func animalListQueryCandidatePrecedes(
        _ lhs: AnimalListQueryCandidate,
        _ rhs: AnimalListQueryCandidate,
        sortOrder: AnimalListQuerySortOrder
    ) -> Bool {
        switch sortOrder {
        case .tagAscending:
            return animalListCandidateTagAscending(lhs, rhs)
        case .tagDescending:
            let tagOrder = lhs.displayTagNumber.localizedStandardCompare(
                rhs.displayTagNumber
            )
            if tagOrder != .orderedSame {
                return tagOrder == .orderedDescending
            }
            return animalListCandidateStableTieBreak(lhs, rhs)
        case .birthDateNewest:
            if lhs.animal.birthDate != rhs.animal.birthDate {
                return lhs.animal.birthDate > rhs.animal.birthDate
            }
            return animalListCandidateStableTieBreak(lhs, rhs)
        case .birthDateOldest:
            if lhs.animal.birthDate != rhs.animal.birthDate {
                return lhs.animal.birthDate < rhs.animal.birthDate
            }
            return animalListCandidateStableTieBreak(lhs, rhs)
        case .sex:
            if lhs.sex.rawValue != rhs.sex.rawValue {
                return lhs.sex.rawValue < rhs.sex.rawValue
            }
            return animalListCandidateTagAscending(lhs, rhs)
        case .animalType:
            let lhsKey = animalTypeSortKey(lhs.animalType)
            let rhsKey = animalTypeSortKey(rhs.animalType)
            if lhsKey != rhsKey {
                return lhsKey < rhsKey
            }
            return animalListCandidateTagAscending(lhs, rhs)
        case .status:
            if lhs.status.rawValue != rhs.status.rawValue {
                return lhs.status.rawValue < rhs.status.rawValue
            }
            return animalListCandidateTagAscending(lhs, rhs)
        case .pasture:
            if lhs.pastureSortKey != rhs.pastureSortKey {
                return lhs.pastureSortKey < rhs.pastureSortKey
            }
            return animalListCandidateTagAscending(lhs, rhs)
        }
    }

    private static func animalListCandidateTagAscending(
        _ lhs: AnimalListQueryCandidate,
        _ rhs: AnimalListQueryCandidate
    ) -> Bool {
        let tagOrder = lhs.displayTagNumber.localizedStandardCompare(
            rhs.displayTagNumber
        )
        if tagOrder != .orderedSame {
            return tagOrder == .orderedAscending
        }
        return animalListCandidateStableTieBreak(lhs, rhs)
    }

    private static func animalListCandidateStableTieBreak(
        _ lhs: AnimalListQueryCandidate,
        _ rhs: AnimalListQueryCandidate
    ) -> Bool {
        let nameOrder = lhs.animal.name.localizedStandardCompare(
            rhs.animal.name
        )
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.animal.id.uuidString < rhs.animal.id.uuidString
    }

    private static func animalTypeSortKey(_ type: AnimalType?) -> Int {
        switch type {
        case .calf: return 0
        case .heifer: return 1
        case .steer: return 2
        case .cow: return 3
        case .bull: return 4
        case nil: return Int.max
        }
    }

    private static func animalListDisplayTagNumber(
        _ animal: CDAnimal
    ) -> String {
        let primary = CoreDataAnimalProjection.managedTags(animal)
            .first { $0.isActive && $0.isPrimary }
        return primary?.number
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func animalListPastureSortKey(
        _ animal: CDAnimal
    ) -> String {
        if animal.activeWorkingSession != nil {
            return "0-working-pen"
        }
        if let name = animal.currentPasture?.name, !name.isEmpty {
            return "1-\(name.lowercased())"
        }
        return "2-no-pasture"
    }

    private static func hydrateAnimalSummaryCandidates(
        _ candidates: [CDAnimal],
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> [CDAnimal] {
        let ids = candidates.map(\.id)
        guard !ids.isEmpty else { return [] }
        let predicateIDs = ids.map { $0 as NSUUID }

        let request = NSFetchRequest<CDAnimal>(
            entityName: CDAnimal.coreDataEntityName
        )
        request.predicate = NSPredicate(
            format: "herd == %@ AND id IN %@",
            herd,
            predicateIDs
        )
        request.relationshipKeyPathsForPrefetching = animalSummaryPrefetchPaths
        let fetched = try context.fetch(request)

        guard fetched.count == ids.count else {
            throw CoreDataReadModelError.inconsistentAnimalPage(
                expected: ids.count,
                fetched: fetched.count
            )
        }

        let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        return try ids.map { id in
            guard let animal = byID[id] else {
                throw CoreDataReadModelError.inconsistentAnimalPage(
                    expected: ids.count,
                    fetched: fetched.count
                )
            }
            return animal
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
            try context.setQueryGenerationFrom(.current)
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

    private static func validateAnimalApplicationIDs(
        herd: CDHerd,
        herdID: UUID,
        in context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSDictionary>(
            entityName: CDAnimal.coreDataEntityName
        )
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        request.predicate = NSPredicate(format: "herd == %@", herd)

        var seenIDs = Set<UUID>()
        for row in try context.fetch(request) {
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
                    entity: CDAnimal.coreDataEntityName,
                    id: id,
                    herdID: herdID
                )
            }
        }
    }

    private static func validateAnimalListTagIntegrity(
        herd: CDHerd,
        herdID: UUID,
        in context: NSManagedObjectContext
    ) throws {
        let crossHerdTagRequest = NSFetchRequest<CDAnimalTag>(
            entityName: CDAnimalTag.coreDataEntityName
        )
        crossHerdTagRequest.predicate = NSPredicate(
            format: "animal.herd == %@ AND herd != %@",
            herd,
            herd
        )
        crossHerdTagRequest.fetchLimit = 1
        crossHerdTagRequest.relationshipKeyPathsForPrefetching = ["herd", "animal"]

        if let tag = try context.fetch(crossHerdTagRequest).first {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDAnimalTag.coreDataEntityName,
                id: tag.id,
                expectedHerdID: herdID,
                actualHerdID: tag.herd.id
            )
        }

        let cardinalityRequest = NSFetchRequest<CDAnimal>(
            entityName: CDAnimal.coreDataEntityName
        )
        cardinalityRequest.predicate = NSPredicate(
            format: """
            herd == %@ AND
            SUBQUERY(tags, $tag, $tag.isActive == YES).@count > 0 AND
            SUBQUERY(
                tags,
                $tag,
                $tag.isActive == YES AND $tag.isPrimary == YES
            ).@count != 1
            """,
            herd
        )
        cardinalityRequest.fetchLimit = 1
        cardinalityRequest.relationshipKeyPathsForPrefetching = ["tags"]

        if let animal = try context.fetch(cardinalityRequest).first {
            try validateTagRelationships(
                animal,
                herdID: herdID
            )
        }
    }

    private static func validateAnimalListQueryIntegrity(
        query: AnimalListFilterQuery?,
        herd: CDHerd,
        herdID: UUID,
        in context: NSManagedObjectContext
    ) throws {
        let invalidEnumRequest = NSFetchRequest<CDAnimal>(
            entityName: CDAnimal.coreDataEntityName
        )
        invalidEnumRequest.predicate = NSPredicate(
            format: """
            herd == %@ AND (
                NOT (sexRawValue IN %@) OR
                NOT (statusRawValue IN %@)
            )
            """,
            herd,
            Sex.allCases.map(\.rawValue),
            AnimalStatus.allCases.map(\.rawValue)
        )
        invalidEnumRequest.fetchLimit = 1

        if let animal = try context.fetch(invalidEnumRequest).first {
            _ = try CoreDataAnimalProjection.sex(animal)
            _ = try CoreDataAnimalProjection.status(animal)
        }

        let invalidPastureRequest = NSFetchRequest<CDAnimal>(
            entityName: CDAnimal.coreDataEntityName
        )
        invalidPastureRequest.predicate = NSPredicate(
            format: """
            herd == %@ AND
            currentPasture != nil AND
            currentPasture.herd != %@
            """,
            herd,
            herd
        )
        invalidPastureRequest.fetchLimit = 1
        invalidPastureRequest.relationshipKeyPathsForPrefetching = ["currentPasture"]

        if let animal = try context.fetch(invalidPastureRequest).first,
           let pasture = animal.currentPasture {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDPasture.coreDataEntityName,
                id: pasture.id,
                expectedHerdID: herdID,
                actualHerdID: pasture.herd.id
            )
        }

        let invalidWorkingRequest = NSFetchRequest<CDAnimal>(
            entityName: CDAnimal.coreDataEntityName
        )
        invalidWorkingRequest.predicate = NSPredicate(
            format: """
            herd == %@ AND
            activeWorkingSession != nil AND
            activeWorkingSession.herd != %@
            """,
            herd,
            herd
        )
        invalidWorkingRequest.fetchLimit = 1
        invalidWorkingRequest.relationshipKeyPathsForPrefetching = ["activeWorkingSession"]

        if let animal = try context.fetch(invalidWorkingRequest).first,
           let session = animal.activeWorkingSession {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDWorkingSession.coreDataEntityName,
                id: session.id,
                expectedHerdID: herdID,
                actualHerdID: session.herd.id
            )
        }

        guard query?.animalType != nil || query?.sortOrder == .animalType else {
            return
        }

        let invalidHealthRequest = NSFetchRequest<CDHealthRecord>(
            entityName: CDHealthRecord.coreDataEntityName
        )
        invalidHealthRequest.predicate = NSPredicate(
            format: "animal.herd == %@ AND herd != %@",
            herd,
            herd
        )
        invalidHealthRequest.fetchLimit = 1
        invalidHealthRequest.relationshipKeyPathsForPrefetching = ["animal", "herd"]

        if let record = try context.fetch(invalidHealthRequest).first {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDHealthRecord.coreDataEntityName,
                id: record.id,
                expectedHerdID: herdID,
                actualHerdID: record.herd.id
            )
        }

        let invalidOffspringRequest = NSFetchRequest<CDAnimal>(
            entityName: CDAnimal.coreDataEntityName
        )
        invalidOffspringRequest.predicate = NSPredicate(
            format: "dam.herd == %@ AND herd != %@",
            herd,
            herd
        )
        invalidOffspringRequest.fetchLimit = 1
        invalidOffspringRequest.relationshipKeyPathsForPrefetching = ["dam", "herd"]

        if let offspring = try context.fetch(invalidOffspringRequest).first {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDAnimal.coreDataEntityName,
                id: offspring.id,
                expectedHerdID: herdID,
                actualHerdID: offspring.herd.id
            )
        }
    }

    private static let dashboardAnimalPrefetchPaths = [
        "tags",
        "tags.color",
        "dam",
        "dam.tags",
        "dam.tags.color",
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
            try validateAnimalReadRelationships(
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

    private static func validateAnimalReadRelationships(
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
        if let dam = animal.dam {
            guard dam.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDAnimal.coreDataEntityName,
                    id: dam.id,
                    expectedHerdID: herdID,
                    actualHerdID: dam.herd.id
                )
            }
            try validateTagRelationships(
                dam,
                herdID: herdID
            )
        }

        try validateTagRelationships(
            animal,
            herdID: herdID
        )
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
        for movement in CoreDataAnimalProjection.managedMovementRecords(animal) {
            guard movement.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDMovementRecord.coreDataEntityName,
                    id: movement.id,
                    expectedHerdID: herdID,
                    actualHerdID: movement.herd.id
                )
            }
        }
        for statusRecord in CoreDataAnimalProjection.managedStatusRecords(animal) {
            guard statusRecord.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDStatusRecord.coreDataEntityName,
                    id: statusRecord.id,
                    expectedHerdID: herdID,
                    actualHerdID: statusRecord.herd.id
                )
            }
        }
    }

    private static func validateAnimalTypeRelationships(
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

    private static func validateTagRelationships(
        _ animal: CDAnimal,
        herdID: UUID
    ) throws {
        let tags = CoreDataAnimalProjection.managedTags(animal)
        for tag in tags {
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

        let activeTags = tags.filter(\.isActive)
        guard activeTags.isEmpty || activeTags.filter(\.isPrimary).count == 1 else {
            throw CoreDataReadModelError.invalidActivePrimaryTagCardinality(
                animalID: animal.id,
                activeTagCount: activeTags.count,
                primaryTagCount: activeTags.filter(\.isPrimary).count
            )
        }
    }

    private static let animalSummaryPrefetchPaths = [
        "tags",
        "tags.color",
        "dam",
        "dam.tags",
        "dam.tags.color",
        "currentPasture",
        "activeWorkingSession",
        "pregnancyChecks",
        "healthRecords",
        "movementRecords",
        "statusRecords",
        "damOffspring"
    ]

    private static func missingPrimaryTagPredicate() -> NSPredicate {
        NSPredicate(
            format: """
            SUBQUERY(
                tags,
                $tag,
                $tag.isActive == YES AND
                $tag.isPrimary == YES AND
                $tag.number != ""
            ).@count == 0
            """
        )
    }

    private static func animalListPredicate(
        query: AnimalListFilterQuery?,
        herd: CDHerd
    ) -> NSPredicate {
        var predicates: [NSPredicate] = [
            NSPredicate(format: "herd == %@", herd)
        ]
        guard let query else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        if !query.showRemovedStatuses {
            predicates.append(
                NSPredicate(
                    format: "statusRawValue == %@",
                    AnimalStatus.active.rawValue
                )
            )
        }
        if !query.showArchivedRecords {
            predicates.append(NSPredicate(format: "isArchived == NO"))
        }
        if let sex = query.sex {
            predicates.append(
                NSPredicate(format: "sexRawValue == %@", sex.rawValue)
            )
        }
        if let status = query.status {
            predicates.append(
                NSPredicate(format: "statusRawValue == %@", status.rawValue)
            )
        }

        switch query.pasture {
        case .any:
            break
        case .noPasture:
            predicates.append(NSPredicate(format: "activeWorkingSession == nil"))
            predicates.append(NSPredicate(format: "currentPasture == nil"))
        case .pasture(let pastureID):
            predicates.append(
                NSPredicate(
                    format: "currentPasture.id == %@",
                    pastureID as NSUUID
                )
            )
        }

        switch query.location {
        case .any:
            break
        case .pasture:
            predicates.append(NSPredicate(format: "activeWorkingSession == nil"))
        case .workingPen:
            predicates.append(NSPredicate(format: "activeWorkingSession != nil"))
        }

        switch query.recordIssue {
        case .any:
            break
        case .missingPasture:
            predicates.append(
                NSPredicate(
                    format: "statusRawValue == %@",
                    AnimalStatus.active.rawValue
                )
            )
            predicates.append(NSPredicate(format: "isArchived == NO"))
            predicates.append(NSPredicate(format: "activeWorkingSession == nil"))
            predicates.append(NSPredicate(format: "currentPasture == nil"))
        case .missingTag:
            predicates.append(
                NSPredicate(
                    format: "statusRawValue == %@",
                    AnimalStatus.active.rawValue
                )
            )
            predicates.append(NSPredicate(format: "isArchived == NO"))
            predicates.append(missingPrimaryTagPredicate())
        case .unknownSex:
            predicates.append(
                NSPredicate(
                    format: "statusRawValue == %@",
                    AnimalStatus.active.rawValue
                )
            )
            predicates.append(NSPredicate(format: "isArchived == NO"))
            predicates.append(
                NSPredicate(format: "sexRawValue == %@", Sex.unknown.rawValue)
            )
        case .archivedActive:
            predicates.append(
                NSPredicate(
                    format: "statusRawValue == %@",
                    AnimalStatus.active.rawValue
                )
            )
            predicates.append(NSPredicate(format: "isArchived == YES"))
        }

        let search = query.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            predicates.append(
                NSCompoundPredicate(
                    orPredicateWithSubpredicates: [
                        NSPredicate(
                            format: "name CONTAINS[cd] %@",
                            search
                        ),
                        NSPredicate(
                            format: """
                            SUBQUERY(
                                tags,
                                $tag,
                                $tag.isActive == YES AND
                                $tag.isPrimary == YES AND
                                $tag.number CONTAINS[cd] %@
                            ).@count > 0
                            """,
                            search
                        )
                    ]
                )
            )
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private static func animalReferencePredicate(
        query: AnimalReferenceQuery,
        herd: CDHerd
    ) -> NSPredicate {
        var predicates: [NSPredicate] = [
            NSPredicate(format: "herd == %@", herd),
            NSPredicate(
                format: "statusRawValue == %@",
                AnimalStatus.active.rawValue
            ),
            NSPredicate(format: "isArchived == NO")
        ]

        switch query.pastureScope {
        case .any:
            break
        case .pasture(let pastureID):
            predicates.append(
                NSPredicate(
                    format: "currentPasture.id == %@",
                    pastureID as NSUUID
                )
            )
        case .notPasture(let pastureID):
            predicates.append(
                NSCompoundPredicate(
                    orPredicateWithSubpredicates: [
                        NSPredicate(format: "currentPasture == nil"),
                        NSPredicate(
                            format: "currentPasture.id != %@",
                            pastureID as NSUUID
                        )
                    ]
                )
            )
        case .assignedPasture:
            predicates.append(NSPredicate(format: "currentPasture != nil"))
        }

        switch query.location {
        case .any:
            break
        case .pasture:
            predicates.append(NSPredicate(format: "activeWorkingSession == nil"))
        case .workingPen:
            predicates.append(NSPredicate(format: "activeWorkingSession != nil"))
        }

        if !query.excludedAnimalIDs.isEmpty {
            predicates.append(
                NSPredicate(
                    format: "NOT (id IN %@)",
                    query.excludedAnimalIDs.map { $0 as NSUUID }
                )
            )
        }

        let search = query.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            predicates.append(
                NSCompoundPredicate(
                    orPredicateWithSubpredicates: [
                        NSPredicate(
                            format: "name CONTAINS[cd] %@",
                            search
                        ),
                        NSPredicate(
                            format: """
                            SUBQUERY(
                                tags,
                                $tag,
                                $tag.isActive == YES AND
                                $tag.isPrimary == YES AND
                                $tag.number CONTAINS[cd] %@
                            ).@count > 0
                            """,
                            search
                        ),
                        NSPredicate(
                            format: "currentPasture.name CONTAINS[cd] %@",
                            search
                        )
                    ]
                )
            )
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private static func taggedAnimalListPredicate(
        query: AnimalListFilterQuery?,
        herd: CDHerd
    ) -> NSPredicate {
        var predicates: [NSPredicate] = [
            NSPredicate(format: "herd == %@", herd),
            NSPredicate(format: "animal.herd == %@", herd),
            NSPredicate(format: "isActive == YES"),
            NSPredicate(format: "isPrimary == YES"),
            NSPredicate(format: "number != ''")
        ]
        guard let query else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        if !query.showRemovedStatuses {
            predicates.append(
                NSPredicate(
                    format: "animal.statusRawValue == %@",
                    AnimalStatus.active.rawValue
                )
            )
        }
        if !query.showArchivedRecords {
            predicates.append(NSPredicate(format: "animal.isArchived == NO"))
        }
        if let sex = query.sex {
            predicates.append(
                NSPredicate(format: "animal.sexRawValue == %@", sex.rawValue)
            )
        }
        if let status = query.status {
            predicates.append(
                NSPredicate(format: "animal.statusRawValue == %@", status.rawValue)
            )
        }

        switch query.pasture {
        case .any:
            break
        case .noPasture:
            predicates.append(NSPredicate(format: "animal.activeWorkingSession == nil"))
            predicates.append(NSPredicate(format: "animal.currentPasture == nil"))
        case .pasture(let pastureID):
            predicates.append(
                NSPredicate(
                    format: "animal.currentPasture.id == %@",
                    pastureID as NSUUID
                )
            )
        }

        switch query.location {
        case .any:
            break
        case .pasture:
            predicates.append(NSPredicate(format: "animal.activeWorkingSession == nil"))
        case .workingPen:
            predicates.append(NSPredicate(format: "animal.activeWorkingSession != nil"))
        }

        switch query.recordIssue {
        case .any:
            break
        case .missingPasture:
            predicates.append(
                NSPredicate(
                    format: "animal.statusRawValue == %@",
                    AnimalStatus.active.rawValue
                )
            )
            predicates.append(NSPredicate(format: "animal.isArchived == NO"))
            predicates.append(NSPredicate(format: "animal.activeWorkingSession == nil"))
            predicates.append(NSPredicate(format: "animal.currentPasture == nil"))
        case .missingTag:
            return NSPredicate(value: false)
        case .unknownSex:
            predicates.append(
                NSPredicate(
                    format: "animal.statusRawValue == %@",
                    AnimalStatus.active.rawValue
                )
            )
            predicates.append(NSPredicate(format: "animal.isArchived == NO"))
            predicates.append(
                NSPredicate(
                    format: "animal.sexRawValue == %@",
                    Sex.unknown.rawValue
                )
            )
        case .archivedActive:
            predicates.append(
                NSPredicate(
                    format: "animal.statusRawValue == %@",
                    AnimalStatus.active.rawValue
                )
            )
            predicates.append(NSPredicate(format: "animal.isArchived == YES"))
        }

        let search = query.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            predicates.append(
                NSCompoundPredicate(
                    orPredicateWithSubpredicates: [
                        NSPredicate(
                            format: "animal.name CONTAINS[cd] %@",
                            search
                        ),
                        NSPredicate(
                            format: "number CONTAINS[cd] %@",
                            search
                        )
                    ]
                )
            )
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
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
