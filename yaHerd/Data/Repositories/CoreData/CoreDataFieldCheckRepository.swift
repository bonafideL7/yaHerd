@preconcurrency import CoreData
import Foundation

enum CoreDataFieldCheckFindingMutationOperation: Sendable {
    case add
    case update
    case updateStatus
    case delete
}

enum CoreDataFieldCheckFindingMutationCheckpoint: Sendable {
    case findingMutationStaged(
        operation: CoreDataFieldCheckFindingMutationOperation,
        sessionID: UUID,
        findingID: UUID
    )
    case missingSynchronizationStaged(
        operation: CoreDataFieldCheckFindingMutationOperation,
        sessionID: UUID,
        findingID: UUID
    )
}

@MainActor
final class CoreDataFieldCheckRepository: FieldCheckRepository {
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    private let transactionExecutor: CoreDataTransactionExecutor
    private let animalWriteBoundary: CoreDataAnimalWriteBoundary
    private let fieldCheckWriteGate: CoreDataAsyncSerialGate
    private let pastureResidentWriteCoordinator: CoreDataPastureResidentWriteCoordinator
    private nonisolated let lookup: CoreDataLookup
    private let findingMutationCheckpoint: (@Sendable (
        CoreDataFieldCheckFindingMutationCheckpoint,
        NSManagedObjectContext
    ) throws -> Void)?

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        transactionExecutor: CoreDataTransactionExecutor,
        animalWriteBoundary: CoreDataAnimalWriteBoundary,
        fieldCheckWriteGate: CoreDataAsyncSerialGate,
        pastureResidentWriteCoordinator: CoreDataPastureResidentWriteCoordinator,
        lookup: CoreDataLookup,
        findingMutationCheckpoint: (@Sendable (
            CoreDataFieldCheckFindingMutationCheckpoint,
            NSManagedObjectContext
        ) throws -> Void)? = nil
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.transactionExecutor = transactionExecutor
        self.animalWriteBoundary = animalWriteBoundary
        self.fieldCheckWriteGate = fieldCheckWriteGate
        self.pastureResidentWriteCoordinator = pastureResidentWriteCoordinator
        self.lookup = lookup
        self.findingMutationCheckpoint = findingMutationCheckpoint
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            transactionExecutor: assembly.transactionExecutor,
            animalWriteBoundary: assembly.animalWriteBoundary,
            fieldCheckWriteGate: assembly.fieldCheckWriteGate,
            pastureResidentWriteCoordinator: assembly.pastureResidentWriteCoordinator,
            lookup: assembly.lookup
        )
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly,
        findingMutationCheckpoint: @escaping @Sendable (
            CoreDataFieldCheckFindingMutationCheckpoint,
            NSManagedObjectContext
        ) throws -> Void
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            transactionExecutor: assembly.transactionExecutor,
            animalWriteBoundary: assembly.animalWriteBoundary,
            fieldCheckWriteGate: assembly.fieldCheckWriteGate,
            pastureResidentWriteCoordinator: assembly.pastureResidentWriteCoordinator,
            lookup: assembly.lookup,
            findingMutationCheckpoint: findingMutationCheckpoint
        )
    }

    // MARK: - Reads

    func fetchSessions() throws -> [FieldCheckSessionSummary] {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            let sessions = try Self.fetchSessions(herd: herd, in: context)
            try Self.validateFieldCheckIdentity(herd: herd, in: context)
            return try sessions.map {
                try FieldCheckMapper.makeSessionSummary(from: $0)
            }
        }
    }

    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot? {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            guard let session = try lookup.herdOwned(
                CDFieldCheckSession.self,
                id: id,
                herdID: herdID,
                in: context
            ) else {
                return nil
            }
            try Self.validateFieldCheckIdentity(herd: herd, in: context)
            return try FieldCheckMapper.makeSessionDetail(from: session)
        }
    }

    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            let findings = try Self.fetchFindings(herd: herd, in: context)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                findings,
                herdID: herd.id
            )
            let open = try findings
                .filter { try Self.findingStatus($0) != .resolved }
                .sorted {
                    if $0.recordedAt != $1.recordedAt {
                        return $0.recordedAt > $1.recordedAt
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }
            let selected = limit > 0 ? Array(open.prefix(limit)) : open
            return try selected.map {
                try FieldCheckMapper.makeFindingSnapshot(from: $0)
            }
        }
    }

    // MARK: - Session creation and lifecycle

    func createSession(input: FieldCheckSessionStartInput) async throws -> UUID {
        try await createSession(input: input, beforeSave: nil)
    }

    func createSession(
        input: FieldCheckSessionStartInput,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws -> UUID {
        let lookup = self.lookup
        return try await performWrite(beforeSave: beforeSave) { context, herd in
            guard let pasture = try lookup.herdOwned(
                CDPasture.self,
                id: input.pastureID,
                herdID: herd.id,
                in: context
            ) else {
                throw FieldCheckRepositoryError.pastureNotFound
            }

            let rosterAnimals = try Self.fetchActiveAnimals(
                pasture: pasture,
                herd: herd,
                in: context
            ).sorted(by: Self.rosterSort)

            let session = CDFieldCheckSession(context: context)
            session.id = try CoreDataAnimalMutation.uniqueID(
                for: CDFieldCheckSession.self,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            session.startedAt = input.startedAt
            session.completedAt = nil
            session.notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            session.expectedHeadCountSnapshot = Int64(rosterAnimals.count)
            session.quickCowCount = 0
            session.quickHeiferCount = 0
            session.quickCalfCount = 0
            session.quickBullCount = 0
            session.quickSteerCount = 0
            session.pastureIDSnapshot = pasture.id
            session.pastureNameSnapshot = pasture.name.trimmingCharacters(in: .whitespacesAndNewlines)
            session.pastureArchivedAt = nil
            session.herd = herd
            session.pasture = pasture

            for animal in rosterAnimals {
                _ = try Self.insertAnimalCheck(
                    for: animal,
                    in: session,
                    wasExpectedAtStart: true,
                    countedAt: nil,
                    herd: herd,
                    lookup: lookup,
                    in: context
                )
            }

            return session.id
        }
    }

    func completeSession(id: UUID) async throws {
        try await completeSession(id: id, beforeSave: nil)
    }

    func completeSession(
        id: UUID,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        let lookup = self.lookup
        try await performWrite(beforeSave: beforeSave) { context, herd in
            guard let session = try lookup.herdOwned(
                CDFieldCheckSession.self,
                id: id,
                herdID: herd.id,
                in: context
            ) else {
                throw FieldCheckRepositoryError.sessionNotFound
            }
            guard FieldCheckSessionLockRules.canEditSessionData(
                completedAt: session.completedAt
            ) else {
                return
            }

            try Self.normalizeQuickAnimalTypeCounts(for: session)
            session.completedAt = .now
        }
    }

    func reopenSession(id: UUID) async throws {
        try await reopenSession(id: id, beforeSave: nil)
    }

    func reopenSession(
        id: UUID,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        let lookup = self.lookup
        try await performWrite(beforeSave: beforeSave) { context, herd in
            guard let session = try lookup.herdOwned(
                CDFieldCheckSession.self,
                id: id,
                herdID: herd.id,
                in: context
            ) else {
                throw FieldCheckRepositoryError.sessionNotFound
            }
            session.completedAt = nil
        }
    }

    // MARK: - Session state

    func updateQuickAnimalTypeCounts(
        sessionID: UUID,
        counts: [AnimalType: Int]
    ) async throws {
        try await updateQuickAnimalTypeCounts(
            sessionID: sessionID,
            counts: counts,
            beforeSave: nil
        )
    }

    func updateQuickAnimalTypeCounts(
        sessionID: UUID,
        counts: [AnimalType: Int],
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        let lookup = self.lookup
        try await performWrite(beforeSave: beforeSave) { context, herd in
            guard let session = try lookup.herdOwned(
                CDFieldCheckSession.self,
                id: sessionID,
                herdID: herd.id,
                in: context
            ) else {
                throw FieldCheckRepositoryError.sessionNotFound
            }
            try Self.ensureSessionIsEditable(session)
            try Self.applyQuickAnimalTypeCounts(
                Self.normalizedQuickAnimalTypeCounts(
                    counts,
                    for: session
                ),
                to: session
            )
        }
    }

    func updateNotes(sessionID: UUID, notes: String) async throws {
        try await updateNotes(sessionID: sessionID, notes: notes, beforeSave: nil)
    }

    func updateNotes(
        sessionID: UUID,
        notes: String,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        let lookup = self.lookup
        try await performWrite(beforeSave: beforeSave) { context, herd in
            guard let session = try lookup.herdOwned(
                CDFieldCheckSession.self,
                id: sessionID,
                herdID: herd.id,
                in: context
            ) else {
                throw FieldCheckRepositoryError.sessionNotFound
            }
            try Self.ensureSessionIsEditable(session)
            session.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func setAnimalCheckCounted(
        sessionID: UUID,
        animalCheckID: UUID,
        isCounted: Bool
    ) async throws {
        try await setAnimalCheckCounted(
            sessionID: sessionID,
            animalCheckID: animalCheckID,
            isCounted: isCounted,
            beforeSave: nil
        )
    }

    func setAnimalCheckCounted(
        sessionID: UUID,
        animalCheckID: UUID,
        isCounted: Bool,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        let lookup = self.lookup
        try await performWrite(beforeSave: beforeSave) { context, herd in
            let check = try Self.requiredAnimalCheck(
                id: animalCheckID,
                sessionID: sessionID,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            try Self.ensureSessionIsEditable(check.session)

            if isCounted {
                check.countedAt = .now
                check.missingConfirmedAt = nil
            } else {
                check.countedAt = nil
            }
            try Self.normalizeQuickAnimalTypeCounts(for: check.session)
        }
    }

    func setAnimalCheckMissing(
        sessionID: UUID,
        animalCheckID: UUID,
        isMissing: Bool
    ) async throws {
        try await setAnimalCheckMissing(
            sessionID: sessionID,
            animalCheckID: animalCheckID,
            isMissing: isMissing,
            beforeSave: nil
        )
    }

    func setAnimalCheckMissing(
        sessionID: UUID,
        animalCheckID: UUID,
        isMissing: Bool,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        let lookup = self.lookup
        try await performWrite(beforeSave: beforeSave) { context, herd in
            let check = try Self.requiredAnimalCheck(
                id: animalCheckID,
                sessionID: sessionID,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            try Self.ensureSessionIsEditable(check.session)

            if isMissing {
                check.missingConfirmedAt = .now
                check.countedAt = nil
            } else {
                check.missingConfirmedAt = nil
            }
            try Self.normalizeQuickAnimalTypeCounts(for: check.session)
        }
    }

    // MARK: - Tracked animals

    func addTrackedAnimalToSession(
        sessionID: UUID,
        animalID: UUID,
        checkedAt: Date
    ) async throws {
        try await addTrackedAnimalToSession(
            sessionID: sessionID,
            animalID: animalID,
            checkedAt: checkedAt,
            beforeSave: nil
        )
    }

    func addTrackedAnimalToSession(
        sessionID: UUID,
        animalID: UUID,
        checkedAt: Date,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        let lookup = self.lookup
        try await performWrite(beforeSave: beforeSave) { context, herd in
            guard let session = try lookup.herdOwned(
                CDFieldCheckSession.self,
                id: sessionID,
                herdID: herd.id,
                in: context
            ) else {
                throw FieldCheckRepositoryError.sessionNotFound
            }
            try Self.ensureSessionIsEditable(session)

            guard let animal = try lookup.herdOwned(
                CDAnimal.self,
                id: animalID,
                herdID: herd.id,
                in: context
            ) else {
                throw FieldCheckRepositoryError.animalNotFound
            }
            guard !animal.isArchived,
                  try CoreDataAnimalProjection.status(animal) == .active else {
                throw FieldCheckRepositoryError.animalNotActive
            }

            guard let destinationPasture = try Self.sessionPasture(
                for: session,
                herdID: herd.id,
                lookup: lookup,
                in: context
            ) else {
                throw FieldCheckRepositoryError.pastureNotFound
            }

            if let existing = Self.animalCheck(for: animalID, in: session) {
                existing.countedAt = checkedAt
                existing.missingConfirmedAt = nil
                if animal.currentPasture?.id != destinationPasture.id {
                    try CoreDataAnimalMutation.move(
                        animal,
                        to: destinationPasture,
                        herd: herd,
                        in: context,
                        at: checkedAt
                    )
                    CoreDataAnimalMutation.rotateRevision(animal)
                }
                try Self.normalizeQuickAnimalTypeCounts(for: session)
                return
            }

            if animal.currentPasture?.id != destinationPasture.id {
                try CoreDataAnimalMutation.move(
                    animal,
                    to: destinationPasture,
                    herd: herd,
                    in: context,
                    at: checkedAt
                )
                CoreDataAnimalMutation.rotateRevision(animal)
            }

            _ = try Self.insertAnimalCheck(
                for: animal,
                in: session,
                wasExpectedAtStart: false,
                countedAt: checkedAt,
                herd: herd,
                lookup: lookup,
                in: context
            )
            session.expectedHeadCountSnapshot += 1
            try Self.normalizeQuickAnimalTypeCounts(for: session)
        }
    }

    // MARK: - Findings

    func addFinding(
        sessionID: UUID,
        input: FieldCheckFindingInput
    ) async throws {
        try await addFinding(sessionID: sessionID, input: input, beforeSave: nil)
    }

    func addFinding(
        sessionID: UUID,
        input: FieldCheckFindingInput,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        let lookup = self.lookup
        let findingMutationCheckpoint = self.findingMutationCheckpoint
        try await performWrite(beforeSave: beforeSave) { context, herd in
            guard let session = try lookup.herdOwned(
                CDFieldCheckSession.self,
                id: sessionID,
                herdID: herd.id,
                in: context
            ) else {
                throw FieldCheckRepositoryError.sessionNotFound
            }
            try Self.ensureSessionIsEditable(session)

            let animal = try Self.optionalAnimal(
                id: input.animalID,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            let linkedAnimalID = input.animalID ?? animal?.id
            let check = linkedAnimalID.flatMap {
                Self.animalCheck(for: $0, in: session)
            }

            let finding = CDFieldCheckFinding(context: context)
            finding.id = try CoreDataAnimalMutation.uniqueID(
                for: CDFieldCheckFinding.self,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            finding.recordedAt = input.recordedAt
            finding.typeRawValue = input.type.rawValue
            finding.severityRawValue = input.severity.rawValue
            finding.statusRawValue = input.status.rawValue
            finding.note = input.note.trimmingCharacters(in: .whitespacesAndNewlines)
            finding.animalIDSnapshot = linkedAnimalID
            finding.animalDisplayTagNumberSnapshot = check?.rosterTagNumberSnapshot
                ?? animal.map(Self.primaryTagFields)?.number
            finding.animalDisplayTagColorIDSnapshot = check?.rosterTagColorIDSnapshot
                ?? animal.map(Self.primaryTagFields)?.colorID
            finding.animalNameSnapshot = check?.animalNameSnapshot ?? animal?.name
            finding.pastureNameSnapshot = session.pastureNameSnapshot
            finding.herd = herd
            finding.session = session
            finding.animal = animal

            try findingMutationCheckpoint?(
                .findingMutationStaged(
                    operation: .add,
                    sessionID: sessionID,
                    findingID: finding.id
                ),
                context
            )

            try Self.applyFindingSideEffects(
                input: input,
                linkedAnimalID: linkedAnimalID,
                session: session
            )
        }
    }

    func updateFinding(
        sessionID: UUID,
        findingID: UUID,
        input: FieldCheckFindingInput
    ) async throws {
        try await updateFinding(
            sessionID: sessionID,
            findingID: findingID,
            input: input,
            beforeSave: nil
        )
    }

    func updateFinding(
        sessionID: UUID,
        findingID: UUID,
        input: FieldCheckFindingInput,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        let lookup = self.lookup
        let findingMutationCheckpoint = self.findingMutationCheckpoint
        try await performWrite(beforeSave: beforeSave) { context, herd in
            let finding = try Self.requiredFinding(
                id: findingID,
                sessionID: sessionID,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            let session = finding.session
            try Self.ensureSessionIsEditable(session)

            let oldLinkedAnimalID = finding.animalIDSnapshot
            let oldShouldSyncMissing =
                try Self.findingType(finding) == .missingAnimal
                && Self.findingStatus(finding) != .resolved

            let animal = try Self.optionalAnimal(
                id: input.animalID,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            let linkedAnimalID = input.animalID ?? animal?.id
            let check = linkedAnimalID.flatMap {
                Self.animalCheck(for: $0, in: session)
            }

            finding.recordedAt = input.recordedAt
            finding.typeRawValue = input.type.rawValue
            finding.severityRawValue = input.severity.rawValue
            finding.statusRawValue = input.status.rawValue
            finding.note = input.note.trimmingCharacters(in: .whitespacesAndNewlines)
            finding.animalIDSnapshot = linkedAnimalID
            finding.animalDisplayTagNumberSnapshot = check?.rosterTagNumberSnapshot
                ?? animal.map(Self.primaryTagFields)?.number
            finding.animalDisplayTagColorIDSnapshot = check?.rosterTagColorIDSnapshot
                ?? animal.map(Self.primaryTagFields)?.colorID
            finding.animalNameSnapshot = check?.animalNameSnapshot ?? animal?.name
            finding.pastureNameSnapshot = session.pastureNameSnapshot
            finding.animal = animal

            try findingMutationCheckpoint?(
                .findingMutationStaged(
                    operation: .update,
                    sessionID: sessionID,
                    findingID: findingID
                ),
                context
            )

            let newShouldSyncMissing =
                input.type == .missingAnimal
                && input.status != .resolved

            var affectedAnimalIDs = Set<UUID>()
            if oldShouldSyncMissing, let oldLinkedAnimalID {
                affectedAnimalIDs.insert(oldLinkedAnimalID)
            }
            if newShouldSyncMissing, let linkedAnimalID {
                affectedAnimalIDs.insert(linkedAnimalID)
            }

            for affectedAnimalID in affectedAnimalIDs {
                try Self.syncMissingStatus(
                    forAnimalID: affectedAnimalID,
                    in: session
                )
            }
        }
    }

    func updateFindingStatus(
        sessionID: UUID,
        findingID: UUID,
        status: FieldCheckFindingStatus
    ) async throws {
        try await updateFindingStatus(
            sessionID: sessionID,
            findingID: findingID,
            status: status,
            beforeSave: nil
        )
    }

    func updateFindingStatus(
        sessionID: UUID,
        findingID: UUID,
        status: FieldCheckFindingStatus,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        let lookup = self.lookup
        let findingMutationCheckpoint = self.findingMutationCheckpoint
        try await performWrite(beforeSave: beforeSave) { context, herd in
            let finding = try Self.requiredFinding(
                id: findingID,
                sessionID: sessionID,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            try Self.ensureSessionCanUpdateFindingStatus(finding.session)

            let linkedAnimalID = finding.animalIDSnapshot
            finding.statusRawValue = status.rawValue
            try findingMutationCheckpoint?(
                .findingMutationStaged(
                    operation: .updateStatus,
                    sessionID: sessionID,
                    findingID: findingID
                ),
                context
            )
            if try Self.findingType(finding) == .missingAnimal {
                try Self.syncMissingStatus(
                    forAnimalID: linkedAnimalID,
                    in: finding.session
                )
            }
        }
    }

    func deleteFinding(
        sessionID: UUID,
        findingID: UUID
    ) async throws {
        try await deleteFinding(
            sessionID: sessionID,
            findingID: findingID,
            beforeSave: nil
        )
    }

    func deleteFinding(
        sessionID: UUID,
        findingID: UUID,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        let lookup = self.lookup
        let findingMutationCheckpoint = self.findingMutationCheckpoint
        try await performWrite(beforeSave: beforeSave) { context, herd in
            let finding = try Self.requiredFinding(
                id: findingID,
                sessionID: sessionID,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            let session = finding.session
            try Self.ensureSessionIsEditable(session)

            let linkedAnimalID = finding.animalIDSnapshot
            if try Self.findingType(finding) == .missingAnimal {
                try Self.syncMissingStatus(
                    forAnimalID: linkedAnimalID,
                    in: session,
                    excludingFindingID: finding.id
                )
            }
            try findingMutationCheckpoint?(
                .missingSynchronizationStaged(
                    operation: .delete,
                    sessionID: sessionID,
                    findingID: findingID
                ),
                context
            )
            context.delete(finding)
        }
    }

    // MARK: - Pasture history

    func archiveSessionsForDeletedPastures(
        _ ids: [UUID],
        archivedAt: Date
    ) async throws {
        guard !ids.isEmpty else {
            return
        }
        let targetIDs = Set(ids)
        try await performWrite { context, herd in
            let sessions = try Self.fetchSessions(herd: herd, in: context)
            for session in sessions where targetIDs.contains(session.pastureIDSnapshot) {
                session.pastureArchivedAt = archivedAt
            }
        }
    }

    // MARK: - Transaction boundary

    private func makeReadScope() throws -> (NSManagedObjectContext, UUID) {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        return (contextFactory.makeReadContext(), herdID)
    }

    private func performWrite<Result: Sendable>(
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)? = nil,
        _ operation: @escaping @Sendable (
            NSManagedObjectContext,
            CDHerd
        ) throws -> Result
    ) async throws -> Result {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let gate = fieldCheckWriteGate
        await gate.acquire()
        await animalWriteBoundary.acquireFieldCheck()

        do {
            try pastureResidentWriteCoordinator.beginFieldCheckWrite()
        } catch {
            animalWriteBoundary.releaseFieldCheck()
            await gate.release()
            throw error
        }

        let lookup = self.lookup
        let animalWriteBoundary = self.animalWriteBoundary
        do {
            let result = try await transactionExecutor.performWrite(
                beforeSave: beforeSave,
                afterTransaction: {
                    animalWriteBoundary.releaseFieldCheck()
                }
            ) { context in
                guard let herd = try lookup.herd(id: herdID, in: context) else {
                    throw HerdRepositoryError.missingHerd
                }
                return try operation(context, herd)
            }
            pastureResidentWriteCoordinator.endFieldCheckWrite()
            await gate.release()
            return result
        } catch {
            pastureResidentWriteCoordinator.endFieldCheckWrite()
            await gate.release()
            throw error
        }
    }
}

// MARK: - Core Data helpers

private extension CoreDataFieldCheckRepository {
    nonisolated static func fetchSessions(
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> [CDFieldCheckSession] {
        let request = NSFetchRequest<CDFieldCheckSession>(
            entityName: CDFieldCheckSession.coreDataEntityName
        )
        request.predicate = NSPredicate(format: "herd == %@", herd)
        let sessions = try context.fetch(request)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            sessions,
            herdID: herd.id
        )
        return sessions.sorted {
            if $0.startedAt != $1.startedAt {
                return $0.startedAt > $1.startedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    nonisolated static func fetchFindings(
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> [CDFieldCheckFinding] {
        let request = NSFetchRequest<CDFieldCheckFinding>(
            entityName: CDFieldCheckFinding.coreDataEntityName
        )
        request.predicate = NSPredicate(format: "herd == %@", herd)
        return try context.fetch(request)
    }

    nonisolated static func fetchAnimalChecks(
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> [CDFieldCheckAnimalCheck] {
        let request = NSFetchRequest<CDFieldCheckAnimalCheck>(
            entityName: CDFieldCheckAnimalCheck.coreDataEntityName
        )
        request.predicate = NSPredicate(format: "herd == %@", herd)
        return try context.fetch(request)
    }

    nonisolated static func fetchActiveAnimals(
        pasture: CDPasture,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> [CDAnimal] {
        let request = NSFetchRequest<CDAnimal>(
            entityName: CDAnimal.coreDataEntityName
        )
        request.predicate = NSPredicate(
            format: "herd == %@ AND currentPasture == %@ AND isArchived == NO AND statusRawValue == %@",
            herd,
            pasture,
            AnimalStatus.active.rawValue
        )
        let animals = try context.fetch(request)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            animals,
            herdID: herd.id
        )
        return animals
    }

    nonisolated static func validateFieldCheckIdentity(
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws {
        let sessions = try fetchSessions(herd: herd, in: context)
        let checks = try fetchAnimalChecks(herd: herd, in: context)
        let findings = try fetchFindings(herd: herd, in: context)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            sessions,
            herdID: herd.id
        )
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            checks,
            herdID: herd.id
        )
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            findings,
            herdID: herd.id
        )
    }

    nonisolated static func requiredAnimalCheck(
        id: UUID,
        sessionID: UUID,
        herdID: UUID,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> CDFieldCheckAnimalCheck {
        guard let check = try lookup.herdOwned(
            CDFieldCheckAnimalCheck.self,
            id: id,
            herdID: herdID,
            in: context
        ), check.session.id == sessionID else {
            throw FieldCheckRepositoryError.animalCheckNotFound
        }
        return check
    }

    nonisolated static func requiredFinding(
        id: UUID,
        sessionID: UUID,
        herdID: UUID,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> CDFieldCheckFinding {
        guard let finding = try lookup.herdOwned(
            CDFieldCheckFinding.self,
            id: id,
            herdID: herdID,
            in: context
        ), finding.session.id == sessionID else {
            throw FieldCheckRepositoryError.findingNotFound
        }
        return finding
    }

    nonisolated static func optionalAnimal(
        id: UUID?,
        herdID: UUID,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> CDAnimal? {
        guard let id else {
            return nil
        }
        return try lookup.herdOwned(
            CDAnimal.self,
            id: id,
            herdID: herdID,
            in: context
        )
    }

    nonisolated static func sessionPasture(
        for session: CDFieldCheckSession,
        herdID: UUID,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> CDPasture? {
        if let pasture = session.pasture {
            return pasture
        }
        return try lookup.herdOwned(
            CDPasture.self,
            id: session.pastureIDSnapshot,
            herdID: herdID,
            in: context
        )
    }

    nonisolated static func insertAnimalCheck(
        for animal: CDAnimal,
        in session: CDFieldCheckSession,
        wasExpectedAtStart: Bool,
        countedAt: Date?,
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> CDFieldCheckAnimalCheck {
        let primary = primaryTagFields(animal)
        let damPrimary = animal.dam.map(primaryTagFields)

        let check = CDFieldCheckAnimalCheck(context: context)
        check.id = try CoreDataAnimalMutation.uniqueID(
            for: CDFieldCheckAnimalCheck.self,
            herdID: herd.id,
            lookup: lookup,
            in: context
        )
        check.animalIDSnapshot = animal.id
        check.rosterTagNumberSnapshot = primary.number
        check.rosterTagColorIDSnapshot = primary.colorID
        if animal.dam != nil {
            let damNumber = damPrimary?.number
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            check.damRosterTagNumberSnapshot = damNumber.isEmpty
                ? AnimalDisplayTagFormatter.untaggedPlaceholder
                : damPrimary?.number
            check.damRosterTagColorIDSnapshot = damPrimary?.colorID
        } else {
            check.damRosterTagNumberSnapshot = nil
            check.damRosterTagColorIDSnapshot = nil
        }
        check.animalNameSnapshot = animal.name
        check.animalSexRawValueSnapshot = try CoreDataAnimalProjection.sex(animal).rawValue
        check.animalTypeRawValueSnapshot = try CoreDataAnimalProjection.animalType(animal).rawValue
        check.wasExpectedAtStart = wasExpectedAtStart
        check.countedAt = countedAt
        check.missingConfirmedAt = nil
        check.herd = herd
        check.session = session
        check.animal = animal
        return check
    }

    nonisolated static func ensureSessionIsEditable(
        _ session: CDFieldCheckSession?
    ) throws {
        guard let session else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
        guard FieldCheckSessionLockRules.canEditSessionData(
            completedAt: session.completedAt
        ) else {
            throw FieldCheckRepositoryError.sessionCompleted
        }
    }

    nonisolated static func ensureSessionCanUpdateFindingStatus(
        _ session: CDFieldCheckSession?
    ) throws {
        guard let session else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
        guard FieldCheckSessionLockRules.canUpdateFindingStatus(
            completedAt: session.completedAt
        ) else {
            throw FieldCheckRepositoryError.sessionCompleted
        }
    }

    nonisolated static func applyFindingSideEffects(
        input: FieldCheckFindingInput,
        linkedAnimalID: UUID?,
        session: CDFieldCheckSession
    ) throws {
        guard FieldCheckFindingRules.shouldMarkAnimalMissing(for: input.type),
              input.status != .resolved,
              let linkedAnimalID,
              let check = animalCheck(for: linkedAnimalID, in: session) else {
            return
        }

        check.missingConfirmedAt = input.recordedAt
        check.countedAt = nil
        try normalizeQuickAnimalTypeCounts(for: session)
    }

    nonisolated static func syncMissingStatus(
        forAnimalID animalID: UUID?,
        in session: CDFieldCheckSession?,
        excludingFindingID: UUID? = nil
    ) throws {
        guard let animalID,
              let session,
              let check = animalCheck(for: animalID, in: session) else {
            return
        }

        let unresolved = try latestUnresolvedMissingFinding(
            for: animalID,
            in: session,
            excludingFindingID: excludingFindingID
        )
        check.missingConfirmedAt = unresolved?.recordedAt
        if unresolved != nil {
            check.countedAt = nil
        }
        try normalizeQuickAnimalTypeCounts(for: session)
    }

    nonisolated static func latestUnresolvedMissingFinding(
        for animalID: UUID,
        in session: CDFieldCheckSession,
        excludingFindingID: UUID?
    ) throws -> CDFieldCheckFinding? {
        let candidates = try managedFindings(session).filter { finding in
            guard finding.id != excludingFindingID,
                  finding.animalIDSnapshot == animalID,
                  try findingType(finding) == .missingAnimal else {
                return false
            }
            return try findingStatus(finding) != .resolved
        }
        return candidates.max { left, right in
            left.recordedAt < right.recordedAt
        }
    }

    nonisolated static func animalCheck(
        for animalID: UUID,
        in session: CDFieldCheckSession
    ) -> CDFieldCheckAnimalCheck? {
        managedChecks(session).first {
            $0.animalIDSnapshot == animalID
        }
    }

    nonisolated static func currentQuickAnimalTypeCounts(
        for session: CDFieldCheckSession
    ) -> [AnimalType: Int] {
        [
            .cow: max(Int(session.quickCowCount), 0),
            .heifer: max(Int(session.quickHeiferCount), 0),
            .calf: max(Int(session.quickCalfCount), 0),
            .bull: max(Int(session.quickBullCount), 0),
            .steer: max(Int(session.quickSteerCount), 0)
        ]
    }

    nonisolated static func normalizedQuickAnimalTypeCounts(
        _ counts: [AnimalType: Int],
        for session: CDFieldCheckSession
    ) throws -> [AnimalType: Int] {
        FieldCheckQuickCountRules.normalizedCounts(
            counts,
            rosterEntries: try quickCountRosterEntries(for: session)
        )
    }

    nonisolated static func normalizeQuickAnimalTypeCounts(
        for session: CDFieldCheckSession
    ) throws {
        try applyQuickAnimalTypeCounts(
            normalizedQuickAnimalTypeCounts(
                currentQuickAnimalTypeCounts(for: session),
                for: session
            ),
            to: session
        )
    }

    nonisolated static func applyQuickAnimalTypeCounts(
        _ counts: [AnimalType: Int],
        to session: CDFieldCheckSession
    ) throws {
        session.quickCowCount = Int64(max(counts[.cow, default: 0], 0))
        session.quickHeiferCount = Int64(max(counts[.heifer, default: 0], 0))
        session.quickCalfCount = Int64(max(counts[.calf, default: 0], 0))
        session.quickBullCount = Int64(max(counts[.bull, default: 0], 0))
        session.quickSteerCount = Int64(max(counts[.steer, default: 0], 0))
    }

    nonisolated static func quickCountRosterEntries(
        for session: CDFieldCheckSession
    ) throws -> [FieldCheckQuickCountRosterEntry] {
        try managedChecks(session).map { check in
            guard let animalType = AnimalType(
                rawValue: check.animalTypeRawValueSnapshot
            ) else {
                throw CoreDataFieldCheckMappingError.invalidAnimalType(
                    checkID: check.id,
                    value: check.animalTypeRawValueSnapshot
                )
            }
            return FieldCheckQuickCountRosterEntry(
                animalType: animalType,
                wasExpectedAtStart: check.wasExpectedAtStart,
                wasCounted: check.countedAt != nil,
                isMissing: check.missingConfirmedAt != nil
            )
        }
    }

    nonisolated static func findingType(
        _ finding: CDFieldCheckFinding
    ) throws -> FieldCheckFindingType {
        guard let result = FieldCheckFindingType(
            rawValue: finding.typeRawValue
        ) else {
            throw CoreDataFieldCheckMappingError.invalidFindingType(
                findingID: finding.id,
                value: finding.typeRawValue
            )
        }
        return result
    }

    nonisolated static func findingStatus(
        _ finding: CDFieldCheckFinding
    ) throws -> FieldCheckFindingStatus {
        guard let result = FieldCheckFindingStatus(
            rawValue: finding.statusRawValue
        ) else {
            throw CoreDataFieldCheckMappingError.invalidFindingStatus(
                findingID: finding.id,
                value: finding.statusRawValue
            )
        }
        return result
    }

    nonisolated static func primaryTagFields(
        _ animal: CDAnimal
    ) -> AnimalPrimaryTagFields {
        CoreDataAnimalProjection.primaryTagFields(
            CoreDataAnimalProjection.managedTags(animal)
        )
    }

    nonisolated static func rosterSort(
        _ left: CDAnimal,
        _ right: CDAnimal
    ) -> Bool {
        let leftPrimary = primaryTagFields(left).number
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rightPrimary = primaryTagFields(right).number
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lhs = leftPrimary.isEmpty ? left.name : leftPrimary
        let rhs = rightPrimary.isEmpty ? right.name : rightPrimary
        let comparison = lhs.localizedStandardCompare(rhs)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return left.id.uuidString < right.id.uuidString
    }

    nonisolated static func managedChecks(
        _ session: CDFieldCheckSession
    ) -> [CDFieldCheckAnimalCheck] {
        (session.animalChecks?.allObjects as? [CDFieldCheckAnimalCheck]) ?? []
    }

    nonisolated static func managedFindings(
        _ session: CDFieldCheckSession
    ) -> [CDFieldCheckFinding] {
        (session.findings?.allObjects as? [CDFieldCheckFinding]) ?? []
    }
}
