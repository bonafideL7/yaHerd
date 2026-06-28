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

        session.quickCowCount = max(counts[.cow, default: 0], 0)
        session.quickHeiferCount = max(counts[.heifer, default: 0], 0)
        session.quickCalfCount = max(counts[.calf, default: 0], 0)
        session.quickBullCount = max(counts[.bull, default: 0], 0)
        session.quickSteerCount = max(counts[.steer, default: 0], 0)
        try context.save()
    }

    func updateNotes(sessionID: UUID, notes: String) throws {
        guard let session = try fetchSession(id: sessionID) else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
        session.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool) throws {
        let check = try fetchAnimalCheck(id: animalCheckID, sessionID: sessionID)
        if isCounted {
            check.countedAt = .now
            check.missingConfirmedAt = nil
        } else {
            check.countedAt = nil
        }
        try context.save()
    }

    func setAnimalCheckNeedsAttention(sessionID: UUID, animalCheckID: UUID, needsAttention: Bool) throws {
        let check = try fetchAnimalCheck(id: animalCheckID, sessionID: sessionID)
        check.needsAttention = needsAttention
        try context.save()
    }

    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) throws {
        let check = try fetchAnimalCheck(id: animalCheckID, sessionID: sessionID)
        if isMissing {
            check.missingConfirmedAt = .now
            check.countedAt = nil
        } else {
            check.missingConfirmedAt = nil
        }
        try context.save()
    }

    func addFinding(sessionID: UUID, input: FieldCheckFindingInput) throws {
        guard let session = try fetchSession(id: sessionID) else {
            throw FieldCheckRepositoryError.sessionNotFound
        }

        let finding = FieldCheckFinding(
            recordedAt: input.recordedAt,
            type: input.type,
            severity: input.severity,
            status: input.status,
            note: input.note.trimmingCharacters(in: .whitespacesAndNewlines),
            animal: try fetchAnimal(id: input.animalID),
            session: session
        )
        try ensureUniqueFindingPublicID(finding)
        context.insert(finding)
        try context.save()
    }

    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus) throws {
        let finding = try fetchFinding(id: findingID, sessionID: sessionID)
        finding.status = status
        try context.save()
    }

    func deleteFinding(sessionID: UUID, findingID: UUID) throws {
        let finding = try fetchFinding(id: findingID, sessionID: sessionID)
        context.delete(finding)
        try context.save()
    }

    func completeSession(id: UUID) throws {
        guard let session = try fetchSession(id: id) else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
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

        let identifierSet = Set(ids)
        let descriptor = FetchDescriptor<FieldCheckSession>()
        let sessionsToDelete = try context.fetch(descriptor)
            .filter { session in
                guard let pastureID = session.pastureID else { return false }
                return identifierSet.contains(pastureID)
            }

        for session in sessionsToDelete {
            context.delete(session)
        }

        try context.save()
    }

    private func ensureUniqueSessionPublicID(_ session: FieldCheckSession) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<FieldCheckSession>()).map(\.publicID))
        while existingIDs.contains(session.publicID) {
            session.publicID = UUID()
        }
    }

    private func ensureUniqueAnimalCheckPublicID(_ check: FieldCheckAnimalCheck) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<FieldCheckAnimalCheck>()).map(\.publicID))
        while existingIDs.contains(check.publicID) {
            check.publicID = UUID()
        }
    }

    private func ensureUniqueFindingPublicID(_ finding: FieldCheckFinding) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<FieldCheckFinding>()).map(\.publicID))
        while existingIDs.contains(finding.publicID) {
            finding.publicID = UUID()
        }
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
                check.publicID == id
            }
        )
        guard let check = try context.fetch(descriptor).first,
              check.session?.publicID == sessionID else {
            throw FieldCheckRepositoryError.animalCheckNotFound
        }
        return check
    }

    private func fetchFinding(id: UUID, sessionID: UUID) throws -> FieldCheckFinding {
        let descriptor = FetchDescriptor<FieldCheckFinding>(
            predicate: #Predicate<FieldCheckFinding> { finding in
                finding.publicID == id
            }
        )
        guard let finding = try context.fetch(descriptor).first,
              finding.session?.publicID == sessionID else {
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
