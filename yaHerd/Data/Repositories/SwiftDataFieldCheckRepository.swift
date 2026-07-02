import Foundation
import SwiftData

struct SwiftDataFieldCheckRepository: FieldCheckRepository {
    let context: ModelContext

    func fetchSessions() throws -> [FieldCheckSessionSummary] {
        let descriptor = FetchDescriptor<FieldCheckSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return try context.fetch(descriptor).map(FieldCheckMapper.makeSessionSummary)
    }

    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot? {
        guard let session = try fetchSession(id: id) else { return nil }
        return FieldCheckMapper.makeSessionDetail(from: session)
    }

    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] {
        let descriptor = FetchDescriptor<FieldCheckFinding>(sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
        let findings = try context.fetch(descriptor)
            .filter { $0.status != .resolved }

        if limit > 0 {
            return Array(findings.prefix(limit)).map(FieldCheckMapper.makeFindingSnapshot)
        }
        return findings.map(FieldCheckMapper.makeFindingSnapshot)
    }

    func createSession(input: FieldCheckSessionStartInput) throws -> UUID {
        guard let pasture = try fetchPasture(id: input.pastureID) else {
            throw FieldCheckRepositoryError.pastureNotFound
        }

        let rosterAnimals = pasture.animals
            .filter(\.isActiveInHerd)
            .sorted { left, right in
                let lhs = left.displayTagNumber.isEmpty ? left.name : left.displayTagNumber
                let rhs = right.displayTagNumber.isEmpty ? right.name : right.displayTagNumber
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        let session = FieldCheckSession(
            startedAt: input.startedAt,
            completedAt: nil,
            notes: input.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            expectedHeadCountSnapshot: rosterAnimals.count,
            pastureID: pasture.publicID,
            pasture: pasture
        )
        try ensureUniqueSessionPublicID(session)
        context.insert(session)

        for animal in rosterAnimals {
            let check = FieldCheckAnimalCheck(
                rosterTagNumber: animal.displayTagNumber,
                rosterTagColorID: animal.displayTagColorID,
                animalName: animal.name,
                animalSex: animal.sex ?? .unknown,
                wasExpectedAtStart: true,
                animal: animal,
                session: session
            )
            try ensureUniqueAnimalCheckPublicID(check)
            context.insert(check)
        }

        try context.save()
        return session.publicID
    }

    func updateQuickAnimalTypeCounts(sessionID: UUID, counts: [AnimalType: Int]) throws {
        guard let session = try fetchSession(id: sessionID) else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
        try ensureSessionIsEditable(session)

        applyQuickAnimalTypeCounts(
            normalizedQuickAnimalTypeCounts(counts, for: session),
            to: session
        )
        try context.save()
    }

    func updateNotes(sessionID: UUID, notes: String) throws {
        guard let session = try fetchSession(id: sessionID) else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
        try ensureSessionIsEditable(session)

        session.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool) throws {
        let check = try fetchAnimalCheck(id: animalCheckID, sessionID: sessionID)
        try ensureSessionIsEditable(check.session)

        if isCounted {
            check.countedAt = .now
            check.missingConfirmedAt = nil
        } else {
            check.countedAt = nil
        }
        normalizeQuickAnimalTypeCounts(for: check.session)
        try context.save()
    }

    func setAnimalCheckNeedsAttention(sessionID: UUID, animalCheckID: UUID, needsAttention: Bool) throws {
        let check = try fetchAnimalCheck(id: animalCheckID, sessionID: sessionID)
        try ensureSessionIsEditable(check.session)

        check.needsAttention = needsAttention
        try context.save()
    }

    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) throws {
        let check = try fetchAnimalCheck(id: animalCheckID, sessionID: sessionID)
        try ensureSessionIsEditable(check.session)

        if isMissing {
            check.missingConfirmedAt = .now
            check.countedAt = nil
        } else {
            check.missingConfirmedAt = nil
        }
        normalizeQuickAnimalTypeCounts(for: check.session)
        try context.save()
    }

    func addFinding(sessionID: UUID, input: FieldCheckFindingInput) throws {
        guard let session = try fetchSession(id: sessionID) else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
        try ensureSessionIsEditable(session)

        let animal = try fetchAnimal(id: input.animalID)
        let finding = FieldCheckFinding(
            recordedAt: input.recordedAt,
            type: input.type,
            severity: input.severity,
            status: input.status,
            note: input.note.trimmingCharacters(in: .whitespacesAndNewlines),
            animal: animal,
            session: session
        )
        try ensureUniqueFindingPublicID(finding)
        context.insert(finding)
        applyFindingSideEffects(input: input, linkedAnimal: animal, session: session)
        try context.save()
    }

    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus) throws {
        let finding = try fetchFinding(id: findingID, sessionID: sessionID)
        try ensureSessionIsEditable(finding.session)

        finding.status = status
        try context.save()
    }

    func deleteFinding(sessionID: UUID, findingID: UUID) throws {
        let finding = try fetchFinding(id: findingID, sessionID: sessionID)
        try ensureSessionIsEditable(finding.session)

        context.delete(finding)
        try context.save()
    }

    func completeSession(id: UUID) throws {
        guard let session = try fetchSession(id: id) else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
        guard FieldCheckSessionLockRules.isEditable(completedAt: session.completedAt) else { return }

        normalizeQuickAnimalTypeCounts(for: session)
        session.completedAt = .now
        try context.save()
    }

    func reopenSession(id: UUID) throws {
        guard let session = try fetchSession(id: id) else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
        session.completedAt = nil
        try context.save()
    }

    func deleteSessions(forPastureIDs ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        for pastureID in Set(ids) {
            let descriptor = FetchDescriptor<FieldCheckSession>(
                predicate: #Predicate<FieldCheckSession> { session in
                    session.pastureID == pastureID
                }
            )
            let sessionsToDelete = try context.fetch(descriptor)
            for session in sessionsToDelete {
                context.delete(session)
            }
        }

        try context.save()
    }


    private func ensureSessionIsEditable(_ session: FieldCheckSession?) throws {
        guard let session else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
        guard FieldCheckSessionLockRules.isEditable(completedAt: session.completedAt) else {
            throw FieldCheckRepositoryError.sessionCompleted
        }
    }

    private func applyFindingSideEffects(
        input: FieldCheckFindingInput,
        linkedAnimal: Animal?,
        session: FieldCheckSession
    ) {
        guard FieldCheckFindingRules.shouldMarkAnimalMissing(for: input.type) else { return }
        guard let linkedAnimal else { return }
        guard let check = animalCheck(for: linkedAnimal.publicID, in: session) else { return }

        check.missingConfirmedAt = input.recordedAt
        check.countedAt = nil
        check.needsAttention = true
        normalizeQuickAnimalTypeCounts(for: session)
    }

    private func animalCheck(for animalID: UUID, in session: FieldCheckSession) -> FieldCheckAnimalCheck? {
        session.animalChecks.first { check in
            check.animal?.publicID == animalID
        }
    }

    private func currentQuickAnimalTypeCounts(for session: FieldCheckSession) -> [AnimalType: Int] {
        [
            .cow: max(session.quickCowCount, 0),
            .heifer: max(session.quickHeiferCount, 0),
            .calf: max(session.quickCalfCount, 0),
            .bull: max(session.quickBullCount, 0),
            .steer: max(session.quickSteerCount, 0)
        ]
    }

    private func normalizedQuickAnimalTypeCounts(
        _ counts: [AnimalType: Int],
        for session: FieldCheckSession
    ) -> [AnimalType: Int] {
        FieldCheckQuickCountRules.normalizedCounts(
            counts,
            rosterEntries: quickCountRosterEntries(for: session)
        )
    }

    private func normalizeQuickAnimalTypeCounts(for session: FieldCheckSession?) {
        guard let session else { return }
        let normalizedCounts = normalizedQuickAnimalTypeCounts(
            currentQuickAnimalTypeCounts(for: session),
            for: session
        )
        applyQuickAnimalTypeCounts(normalizedCounts, to: session)
    }

    private func applyQuickAnimalTypeCounts(
        _ counts: [AnimalType: Int],
        to session: FieldCheckSession
    ) {
        session.quickCowCount = max(counts[.cow, default: 0], 0)
        session.quickHeiferCount = max(counts[.heifer, default: 0], 0)
        session.quickCalfCount = max(counts[.calf, default: 0], 0)
        session.quickBullCount = max(counts[.bull, default: 0], 0)
        session.quickSteerCount = max(counts[.steer, default: 0], 0)
    }

    private func quickCountRosterEntries(for session: FieldCheckSession) -> [FieldCheckQuickCountRosterEntry] {
        session.animalChecks.map { check in
            FieldCheckQuickCountRosterEntry(
                animalType: animalType(for: check),
                wasExpectedAtStart: check.wasExpectedAtStart,
                wasCounted: check.wasCounted,
                isMissing: check.isMissing
            )
        }
    }

    private func animalType(for check: FieldCheckAnimalCheck) -> AnimalType {
        check.animal?.animalType ?? fallbackAnimalType(for: check.animalSex)
    }

    private func fallbackAnimalType(for sex: Sex) -> AnimalType {
        switch sex {
        case .female:
            return .cow
        case .male:
            return .bull
        case .unknown:
            return .bull
        }
    }

    private func ensureUniqueSessionPublicID(_ session: FieldCheckSession) throws {
        while try fieldCheckSessionPublicIDExists(session.publicID, excluding: session) {
            session.publicID = UUID()
        }
    }

    private func ensureUniqueAnimalCheckPublicID(_ check: FieldCheckAnimalCheck) throws {
        while try fieldCheckAnimalCheckPublicIDExists(check.publicID, excluding: check) {
            check.publicID = UUID()
        }
    }

    private func ensureUniqueFindingPublicID(_ finding: FieldCheckFinding) throws {
        while try fieldCheckFindingPublicIDExists(finding.publicID, excluding: finding) {
            finding.publicID = UUID()
        }
    }

    private func fieldCheckSessionPublicIDExists(_ id: UUID, excluding session: FieldCheckSession) throws -> Bool {
        let descriptor = FetchDescriptor<FieldCheckSession>(
            predicate: #Predicate<FieldCheckSession> { existing in
                existing.publicID == id
            }
        )
        return try context.fetch(descriptor).contains { $0 !== session }
    }

    private func fieldCheckAnimalCheckPublicIDExists(_ id: UUID, excluding check: FieldCheckAnimalCheck) throws -> Bool {
        let descriptor = FetchDescriptor<FieldCheckAnimalCheck>(
            predicate: #Predicate<FieldCheckAnimalCheck> { existing in
                existing.publicID == id
            }
        )
        return try context.fetch(descriptor).contains { $0 !== check }
    }

    private func fieldCheckFindingPublicIDExists(_ id: UUID, excluding finding: FieldCheckFinding) throws -> Bool {
        let descriptor = FetchDescriptor<FieldCheckFinding>(
            predicate: #Predicate<FieldCheckFinding> { existing in
                existing.publicID == id
            }
        )
        return try context.fetch(descriptor).contains { $0 !== finding }
    }

    private func fetchSession(id: UUID) throws -> FieldCheckSession? {
        let descriptor = FetchDescriptor<FieldCheckSession>(
            predicate: #Predicate<FieldCheckSession> { session in
                session.publicID == id
            }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchAnimalCheck(id: UUID, sessionID: UUID) throws -> FieldCheckAnimalCheck {
        let descriptor = FetchDescriptor<FieldCheckAnimalCheck>(
            predicate: #Predicate<FieldCheckAnimalCheck> { check in
                check.publicID == id && check.session?.publicID == sessionID
            }
        )
        guard let check = try context.fetch(descriptor).first else {
            throw FieldCheckRepositoryError.animalCheckNotFound
        }
        return check
    }

    private func fetchFinding(id: UUID, sessionID: UUID) throws -> FieldCheckFinding {
        let descriptor = FetchDescriptor<FieldCheckFinding>(
            predicate: #Predicate<FieldCheckFinding> { finding in
                finding.publicID == id && finding.session?.publicID == sessionID
            }
        )
        guard let finding = try context.fetch(descriptor).first else {
            throw FieldCheckRepositoryError.findingNotFound
        }
        return finding
    }

    private func fetchPasture(id: UUID?) throws -> Pasture? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Pasture>(
            predicate: #Predicate<Pasture> { pasture in
                pasture.publicID == id
            }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchAnimal(id: UUID?) throws -> Animal? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Animal>(
            predicate: #Predicate<Animal> { animal in
                animal.publicID == id
            }
        )
        return try context.fetch(descriptor).first
    }
}
