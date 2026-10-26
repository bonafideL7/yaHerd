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
    case invalidAnimalRelationship(
        entity: String,
        id: UUID,
        expectedAnimalID: UUID,
        actualAnimalID: UUID?
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
        case .invalidAnimalRelationship:
            return "The read-model relationship points to another animal."
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
    AnimalListSnapshotReading,
    AnimalListFilteredQueryReading,
    AnimalReferenceQueryReading,
    AnimalParentOptionQueryReading
{
    private let contextFactory: CoreDataContextFactory
    private let lookup: CoreDataLookup
    private let currentHerdID: @MainActor @Sendable () -> UUID?

    init(
        contextFactory: CoreDataContextFactory,
        lookup: CoreDataLookup,
        currentHerdID: @escaping @MainActor @Sendable () -> UUID?
    ) {
        self.contextFactory = contextFactory
        self.lookup = lookup
        self.currentHerdID = currentHerdID
    }

    func fetchDashboardRecords() async throws -> DashboardRecords {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup

        return try await context.perform {
            try Task.checkCancellation()
            try Self.pinCurrentQueryGenerationIfSupported(in: context)
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            // The 25 displayed active Working sessions are a bounded view,
            // not a bound on their complete-Herd application UUID integrity.
            try Self.validateHerdApplicationIDs(
                entityName: CDWorkingSession.coreDataEntityName,
                herd: herd,
                herdID: herdID,
                in: context
            )
            try Self.validateHerdApplicationIDs(
                entityName: CDWorkingQueueItem.coreDataEntityName,
                herd: herd,
                herdID: herdID,
                in: context
            )

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
                context: context,
                herdAnimals: animals
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
                }.sorted { left, right in
                    if left.date != right.date { return left.date > right.date }
                    return left.id.uuidString < right.id.uuidString
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
            try Self.pinCurrentQueryGenerationIfSupported(in: context)
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            // The filtered Dashboard Animal lists must reject identities
            // duplicated by excluded (e.g. archived) selected-Herd records.
            try Self.validateAnimalApplicationIDs(
                herd: herd, herdID: herdID, in: context
            )

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
            // Group identity validation and all resident count queries must
            // observe the same committed store generation.
            try Self.pinCurrentQueryGenerationIfSupported(in: context)
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            // The independent Pasture list must reject Animal UUID collisions
            // outside its counted active resident cohort, as full Dashboard does.
            try Self.validateAnimalApplicationIDs(
                herd: herd, herdID: herdID, in: context
            )
            return try Self.dashboardPastureRecords(
                herd: herd,
                herdID: herdID,
                context: context
            )
        }
    }

    /// Resolve the unfiltered Animal list in one generation rather than
    /// concatenating independently pinned pages across concurrent writes.
    func fetchAnimalSummarySnapshot() async throws -> [AnimalSummary] {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup
        let referenceDate = Date()
        let calendar = Calendar.current

        return try await context.perform {
            try Task.checkCancellation()
            try Self.pinCurrentQueryGenerationIfSupported(in: context)
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            try Self.validateAnimalApplicationIDs(herd: herd, herdID: herdID, in: context)
            try Self.validateAnimalListTagIntegrity(herd: herd, herdID: herdID, in: context)
            try Self.validateAnimalListQueryIntegrity(
                query: nil, herd: herd, herdID: herdID, in: context
            )

            let candidates = try Self.fetchLightweightSortedQueryCandidates(
                query: nil,
                sortOrder: .tagAscending,
                herd: herd,
                herdID: herdID,
                referenceDate: referenceDate,
                calendar: calendar,
                offset: 0,
                limit: Int.max,
                in: context
            )
            var summaries: [AnimalSummary] = []
            summaries.reserveCapacity(candidates.count)
            var offset = 0
            while offset < candidates.count {
                try Task.checkCancellation()
                let chunk = Array(
                    candidates.dropFirst(offset).prefix(Self.animalLightweightScanBatchSize)
                )
                let hydrated = try Self.hydrateAnimalSummaryCandidates(
                    chunk, herd: herd, in: context
                )
                for animal in hydrated {
                    try Self.validateAnimalReadRelationships(animal, herdID: herdID)
                    summaries.append(
                        try CoreDataAnimalProjection.summary(
                            animal, now: referenceDate, calendar: calendar
                        )
                    )
                }
                offset += chunk.count
            }
            return summaries
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
            try Self.pinCurrentQueryGenerationIfSupported(in: context)
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

    /// Resolve the complete reference cohort against one pinned Core Data query
    /// generation. Separate fetchAnimalReferencePage calls each create a new
    /// context and are not safe to combine when writes occur between pages.
    /// Parent choices differ from cross-feature active candidate lists:
    /// non-archived inactive/deceased Animals remain available, as before.
    /// Resolve one coherent selected-Herd cohort off the UI actor.
    func fetchParentOptions(excluding excludedAnimalID: UUID?) async throws -> [AnimalParentOption] {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup

        return try await context.perform {
            try Task.checkCancellation()
            try Self.pinCurrentQueryGenerationIfSupported(in: context)
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            try Self.validateAnimalApplicationIDs(herd: herd, herdID: herdID, in: context)
            try Self.validateAnimalListTagIntegrity(herd: herd, herdID: herdID, in: context)

            let request = NSFetchRequest<CDAnimal>(
                entityName: CDAnimal.coreDataEntityName
            )
            var predicates: [NSPredicate] = [
                NSPredicate(format: "herd == %@", herd),
                NSPredicate(format: "isArchived == NO")
            ]
            if let excludedAnimalID {
                predicates.append(NSPredicate(format: "id != %@", excludedAnimalID as NSUUID))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.fetchBatchSize = Self.animalLightweightScanBatchSize

            var options: [AnimalParentOption] = []
            for animal in try context.fetch(request) {
                try Task.checkCancellation()
                try Self.validateAnimalReadRelationships(animal, herdID: herdID)
                options.append(try CoreDataAnimalProjection.parentOption(animal))
            }
            return options.sorted { left, right in
                let order = left.displayName.localizedStandardCompare(right.displayName)
                if order != .orderedSame { return order == .orderedAscending }
                return left.id.uuidString < right.id.uuidString
            }
        }
    }

    func fetchAnimalReferenceSnapshot(
        matching query: AnimalReferenceQuery
    ) async throws -> [AnimalSummary] {
        try Task.checkCancellation()
        let herdID = try await selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup
        let referenceDate = Date()
        let calendar = Calendar.current

        return try await context.perform {
            try Task.checkCancellation()
            try Self.pinCurrentQueryGenerationIfSupported(in: context)
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
                offset: 0,
                limit: Int.max,
                in: context
            )
            var summaries: [AnimalSummary] = []
            summaries.reserveCapacity(candidates.count)

            // Keep SQL IN predicates bounded while all chunks share the same
            // managed-object context and pinned store generation.
            var offset = 0
            while offset < candidates.count {
                try Task.checkCancellation()
                let chunk = Array(
                    candidates.dropFirst(offset).prefix(Self.animalLightweightScanBatchSize)
                )
                let hydrated = try Self.hydrateAnimalSummaryCandidates(
                    chunk,
                    herd: herd,
                    in: context
                )
                for animal in hydrated {
                    try Self.validateAnimalReadRelationships(
                        animal,
                        herdID: herdID
                    )
                    summaries.append(
                        try CoreDataAnimalProjection.summary(
                            animal,
                            now: referenceDate,
                            calendar: calendar
                        )
                    )
                }
                offset += chunk.count
            }
            return summaries
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
            try Self.pinCurrentQueryGenerationIfSupported(in: context)
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
            try Self.pinCurrentQueryGenerationIfSupported(in: context)
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
            try Self.pinCurrentQueryGenerationIfSupported(in: context)
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            // All selected-Herd session IDs matter, including completed
            // sessions excluded from the warning projection.
            try Self.validateHerdApplicationIDs(
                entityName: CDFieldCheckSession.coreDataEntityName,
                herd: herd,
                herdID: herdID,
                in: context
            )

            try Self.validateFieldCheckChildIdentityAndFindingGraph(
                herd: herd,
                herdID: herdID,
                in: context
            )

            let sessionRequest = NSFetchRequest<CDFieldCheckSession>(
                entityName: CDFieldCheckSession.coreDataEntityName
            )
            sessionRequest.predicate = NSPredicate(
                format: """
                herd == %@ AND pastureArchivedAt == nil AND pasture != nil AND (
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
                format: "herd == %@ AND session.herd == %@ AND session.pastureArchivedAt == nil AND session.pasture != nil AND statusRawValue IN %@",
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
            try Self.pinCurrentQueryGenerationIfSupported(in: context)
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            // The Home limit does not constrain complete-Herd template IDs.
            try Self.validateHerdApplicationIDs(
                entityName: CDWorkingTreatmentTemplate.coreDataEntityName,
                herd: herd,
                herdID: herdID,
                in: context
            )

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
                let items = try WorkingMapper.treatmentTemplateItems(template)
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
        try validateHerdApplicationIDs(
            entityName: CDAnimal.coreDataEntityName,
            herd: herd,
            herdID: herdID,
            in: context
        )
    }

    /// Validate an entire Herd's identity scope while retaining only one UUID
    /// and at most one bounded dictionary page. Sorting by the persisted UUID
    /// keeps duplicates adjacent, even when they straddle a fetch-page edge.
    private static func validateHerdApplicationIDs(
        entityName: String,
        herd: CDHerd,
        herdID: UUID,
        in context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        request.predicate = NSPredicate(format: "herd == %@", herd)
        request.sortDescriptors = [
            NSSortDescriptor(key: "id", ascending: true)
        ]
        request.fetchLimit = animalLightweightScanBatchSize

        var previousID: UUID?
        var offset = 0
        while true {
            try Task.checkCancellation()
            request.fetchOffset = offset
            let rows = try context.fetch(request)
            if rows.isEmpty {
                break
            }
            for row in rows {
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
                if previousID == id {
                    throw CoreDataPersistenceError.duplicateApplicationID(
                        entity: entityName,
                        id: id,
                        herdID: herdID
                    )
                }
                previousID = id
            }
            offset += rows.count
            if rows.count < animalLightweightScanBatchSize {
                break
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
        context: NSManagedObjectContext,
        herdAnimals: [CDAnimal]? = nil
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

        // Match the direct Pasture read contract: projecting rest-days from a
        // linked Group is unsafe if two Groups in this Herd share a UUID.
        // Skip the cohort read when no Pasture references a Group.
        if pastures.contains(where: { $0.group != nil }) {
            let groupRequest = NSFetchRequest<CDPastureGroup>(
                entityName: CDPastureGroup.coreDataEntityName
            )
            groupRequest.predicate = NSPredicate(format: "herd == %@", herd)
            let groups = try context.fetch(groupRequest)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                groups,
                herdID: herdID
            )
        }

        // A foreign-Herd Animal may be physically linked to a selected-Herd
        // Pasture through the inverse resident relationship. Excluding it from
        // the active selected-Herd count must not silently accept a graph that
        // the direct Pasture summary and detail readers reject.
        if !pastures.isEmpty {
            let invalidResidentRequest = NSFetchRequest<CDAnimal>(
                entityName: CDAnimal.coreDataEntityName
            )
            invalidResidentRequest.predicate = NSPredicate(
                format: "currentPasture.herd == %@ AND herd != %@",
                herd,
                herd
            )
            invalidResidentRequest.fetchLimit = 1
            if let resident = try context.fetch(invalidResidentRequest).first {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDAnimal.coreDataEntityName,
                    id: resident.id,
                    expectedHerdID: herdID,
                    actualHerdID: resident.herd.id
                )
            }
        }

        // The full Dashboard already has every selected-Herd Animal. The
        // standalone Pasture list needs only one resident-cohort fetch, not a
        // separate COUNT query for each Pasture.
        let residentCandidates: [CDAnimal]
        if let herdAnimals {
            residentCandidates = herdAnimals
        } else if pastures.isEmpty {
            residentCandidates = []
        } else {
            let residentRequest = NSFetchRequest<CDAnimal>(
                entityName: CDAnimal.coreDataEntityName
            )
            residentRequest.predicate = NSPredicate(
                format: """
                herd == %@ AND
                currentPasture != nil AND
                isArchived == NO AND
                statusRawValue == %@
                """,
                herd,
                AnimalStatus.active.rawValue
            )
            residentRequest.fetchBatchSize = 250
            residentRequest.relationshipKeyPathsForPrefetching = ["currentPasture"]
            residentCandidates = try context.fetch(residentRequest)
        }

        // Object IDs disambiguate physical Pastures even when the store
        // contains corrupt duplicate application UUIDs. They stay in Data.
        var activeCountsByPasture: [NSManagedObjectID: Int] = [:]
        for animal in residentCandidates {
            guard !animal.isArchived,
                  animal.statusRawValue == AnimalStatus.active.rawValue,
                  let currentPasture = animal.currentPasture else {
                continue
            }
            activeCountsByPasture[currentPasture.objectID, default: 0] += 1
        }

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

            return DashboardPastureRecord(
                id: pasture.id,
                name: pasture.name,
                acreage: pasture.acreage?.doubleValue,
                usableAcreage: pasture.usableAcreage?.doubleValue,
                targetAcresPerHead: pasture.targetAcresPerHead?.doubleValue,
                activeAnimalCount: activeCountsByPasture[pasture.objectID, default: 0],
                lastGrazedDate: pasture.lastGrazedDate,
                restDays: pasture.group.map { Int($0.restDays) }
            )
        }
    }

    private static func dashboardWorkingSessionRecord(
        _ session: CDWorkingSession,
        herdID: UUID
    ) throws -> DashboardWorkingSessionRecord {
        // Share the direct Working reader's complete ownership and snapshot
        // contract; partial queue/Herd checks here can accept a graph rejected
        // by the Working list/detail/editor readers.
        try CoreDataWorkingRepository.validateSessionGraph(
            session,
            herdID: herdID
        )

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
        try CoreDataAnimalReadGraphValidator.validateAnimalReadRelationships(
            animal, herdID: herdID
        )
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
        try CoreDataAnimalReadGraphValidator.validateTagRelationships(
            animal, herdID: herdID
        )
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

    private static func validateFieldCheckChildIdentityAndFindingGraph(
        herd: CDHerd,
        herdID: UUID,
        in context: NSManagedObjectContext
    ) throws {
        let corruptRequest = NSFetchRequest<CDFieldCheckFinding>(
            entityName: CDFieldCheckFinding.coreDataEntityName
        )
        corruptRequest.predicate = NSPredicate(
            format: """
            (herd == %@ AND (
                session.herd != %@ OR
                NOT (statusRawValue IN %@)
            )) OR (session.herd == %@ AND herd != %@)
            """,
            herd,
            herd,
            validFindingStatusRawValues,
            herd,
            herd
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

        // Home only hydrates warning sessions, so their inverse children
        // cannot reveal a selected-Herd check attached to a foreign session
        // or a foreign-Herd check attached to completed selected history.
        let corruptCheckRequest = NSFetchRequest<CDFieldCheckAnimalCheck>(
            entityName: CDFieldCheckAnimalCheck.coreDataEntityName
        )
        corruptCheckRequest.predicate = NSPredicate(
            format: """
            (herd == %@ AND session.herd != %@) OR
            (session.herd == %@ AND herd != %@)
            """,
            herd,
            herd,
            herd,
            herd
        )
        corruptCheckRequest.fetchLimit = 1
        corruptCheckRequest.relationshipKeyPathsForPrefetching = ["session", "herd"]

        if let check = try context.fetch(corruptCheckRequest).first {
            let checkHerd = try CoreDataRequiredRelationship.resolve(
                "herd", from: check, as: CDHerd.self
            )
            let session = try CoreDataRequiredRelationship.resolve(
                "session", from: check, as: CDFieldCheckSession.self
            )
            let sessionHerd = try CoreDataRequiredRelationship.resolve(
                "herd", from: session, as: CDHerd.self
            )
            guard checkHerd.objectID == herd.objectID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDFieldCheckAnimalCheck.coreDataEntityName,
                    id: check.id,
                    expectedHerdID: herdID,
                    actualHerdID: checkHerd.id
                )
            }
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDFieldCheckSession.coreDataEntityName,
                id: session.id,
                expectedHerdID: herdID,
                actualHerdID: sessionHerd.id
            )
        }

        // Completed/resolved children are still part of the complete
        // selected-Herd identity scope used by the direct Field Check library.
        for entityName in [
            CDFieldCheckFinding.coreDataEntityName,
            CDFieldCheckAnimalCheck.coreDataEntityName
        ] {
            try validateHerdApplicationIDs(
                entityName: entityName,
                herd: herd,
                herdID: herdID,
                in: context
            )
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

        // Home displays only warning sessions, but all of their historical
        // findings (including resolved ones) share one Herd-scoped identity.
        // The unresolved global count scan cannot detect resolved collisions.
        let allFindings = sessions.flatMap {
            ($0.findings?.allObjects as? [CDFieldCheckFinding]) ?? []
        }
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            allFindings,
            herdID: herdID
        )

        for session in sessions {
            let sessionHerd = try CoreDataRequiredRelationship.resolve(
                "herd", from: session, as: CDHerd.self
            )
            guard sessionHerd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDFieldCheckSession.coreDataEntityName,
                    id: session.id,
                    expectedHerdID: herdID,
                    actualHerdID: sessionHerd.id
                )
            }

            let checks = (session.animalChecks?.allObjects as? [CDFieldCheckAnimalCheck]) ?? []
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                checks,
                herdID: herdID
            )
            for check in checks {
                let checkHerd = try CoreDataRequiredRelationship.resolve(
                    "herd", from: check, as: CDHerd.self
                )
                let linkedSession = try CoreDataRequiredRelationship.resolve(
                    "session", from: check, as: CDFieldCheckSession.self
                )
                guard checkHerd.id == herdID else {
                    throw CoreDataReadModelError.invalidHerdOwnership(
                        entity: CDFieldCheckAnimalCheck.coreDataEntityName,
                        id: check.id,
                        expectedHerdID: herdID,
                        actualHerdID: checkHerd.id
                    )
                }
                guard linkedSession.objectID == session.objectID else {
                    throw CoreDataReadModelError.invalidSessionRelationship(
                        entity: CDFieldCheckAnimalCheck.coreDataEntityName,
                        id: check.id,
                        expectedSessionID: session.id,
                        actualSessionID: linkedSession.id
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

    // Query generations are persistent-store snapshots. In-memory Core Data
    // stores do not support the SQLite history tokens used by production reads.
    // Keep generation pinning for SQLite while allowing in-memory read contexts
    // to observe the state of their coordinator without an invalid token.
    private static func pinCurrentQueryGenerationIfSupported(
        in context: NSManagedObjectContext
    ) throws {
        // In-memory stores used by tests cannot pin SQLite snapshots.
        // Preserve the original generation-pinning semantics for every other
        // configuration, including SQLite, mixed, and unavailable stores.
        let stores = context.persistentStoreCoordinator?.persistentStores ?? []
        if stores.count == 1 && stores[0].type == NSInMemoryStoreType {
            return
        }
        try context.setQueryGenerationFrom(.current)
    }

    private static func validateFindingRelationship(
        _ finding: CDFieldCheckFinding,
        expectedSession: CDFieldCheckSession? = nil,
        herdID: UUID
    ) throws {
        let findingHerd = try CoreDataRequiredRelationship.resolve(
            "herd", from: finding, as: CDHerd.self
        )
        let session = try CoreDataRequiredRelationship.resolve(
            "session", from: finding, as: CDFieldCheckSession.self
        )
        let sessionHerd = try CoreDataRequiredRelationship.resolve(
            "herd", from: session, as: CDHerd.self
        )
        guard findingHerd.id == herdID else {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDFieldCheckFinding.coreDataEntityName,
                id: finding.id,
                expectedHerdID: herdID,
                actualHerdID: findingHerd.id
            )
        }
        guard sessionHerd.id == herdID else {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDFieldCheckSession.coreDataEntityName,
                id: session.id,
                expectedHerdID: herdID,
                actualHerdID: sessionHerd.id
            )
        }
        if let expectedSession,
           session.objectID != expectedSession.objectID {
            throw CoreDataReadModelError.invalidSessionRelationship(
                entity: CDFieldCheckFinding.coreDataEntityName,
                id: finding.id,
                expectedSessionID: expectedSession.id,
                actualSessionID: session.id
            )
        }
    }
}
