import Foundation
import SwiftData

struct SwiftDataFieldCheckRepository: FieldCheckRepository {
    let context: ModelContext

    func fetchSessions() throws -> [FieldCheckSessionSummary] {
        let descriptor = FetchDescriptor<FieldCheckSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let sessions = try context.fetch(descriptor)
        try saveIfNeeded(backfillHistoricalSnapshots(in: sessions))
        return sessions.map(FieldCheckMapper.makeSessionSummary)
    }

    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot? {
        guard let session = try fetchSession(id: id) else { return nil }
        try saveIfNeeded(backfillHistoricalSnapshots(in: session))
        return FieldCheckMapper.makeSessionDetail(from: session)
    }

    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] {
        let descriptor = FetchDescriptor<FieldCheckFinding>(sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
        let findings = try context.fetch(descriptor)
            .filter { $0.status != .resolved }

        try saveIfNeeded(backfillHistoricalSnapshots(for: findings))

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
            pastureNameSnapshot: pasture.name.trimmingCharacters(in: .whitespacesAndNewlines),
            pastureID: pasture.publicID,
            pasture: pasture
        )
        try ensureUniqueSessionPublicID(session)
        context.insert(session)

        for animal in rosterAnimals {
            let check = FieldCheckAnimalCheck(
                animalIDSnapshot: animal.publicID,
                rosterTagNumber: animal.displayTagNumber,
                rosterTagColorID: animal.displayTagColorID,
                damRosterTagNumber: AnimalDisplayTagFormatter.displayTagNumber(for: animal.damAnimal) ?? "",
                damRosterTagColorID: animal.damAnimal?.displayTagColorID,
                animalName: animal.name,
                animalSex: animal.sex ?? .unknown,
                animalType: animal.animalType,
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
        try saveIfNeeded(backfillHistoricalSnapshots(in: session))

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
        try saveIfNeeded(backfillHistoricalSnapshots(in: check.session))

        if isCounted {
            check.countedAt = .now
            check.missingConfirmedAt = nil
        } else {
            check.countedAt = nil
        }
        normalizeQuickAnimalTypeCounts(for: check.session)
        try context.save()
    }

    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool) throws {
        let check = try fetchAnimalCheck(id: animalCheckID, sessionID: sessionID)
        try ensureSessionIsEditable(check.session)
        try saveIfNeeded(backfillHistoricalSnapshots(in: check.session))

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
        try saveIfNeeded(backfillHistoricalSnapshots(in: session))

        let animal = try fetchAnimal(id: input.animalID)
        let check = input.animalID.flatMap { animalCheck(for: $0, in: session) }
        let finding = FieldCheckFinding(
            recordedAt: input.recordedAt,
            type: input.type,
            severity: input.severity,
            status: input.status,
            note: input.note.trimmingCharacters(in: .whitespacesAndNewlines),
            animalIDSnapshot: input.animalID ?? animal?.publicID,
            animalDisplayTagNumberSnapshot: check?.rosterTagNumber ?? animal?.displayTagNumber ?? "",
            animalDisplayTagColorIDSnapshot: check?.rosterTagColorID ?? animal?.displayTagColorID,
            animalNameSnapshot: check?.animalName ?? animal?.name ?? "",
            pastureNameSnapshot: session.pastureNameSnapshot,
            sessionIDSnapshot: session.publicID,
            animal: animal,
            session: session
        )
        try ensureUniqueFindingPublicID(finding)
        context.insert(finding)
        applyFindingSideEffects(input: input, linkedAnimalID: input.animalID ?? animal?.publicID, session: session)
        syncNeedsAttention(
            forAnimalID: input.animalID ?? animal?.publicID,
            in: session,
            includesNewUnresolvedFinding: input.status != .resolved
        )
        try context.save()
    }

    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus) throws {
        let finding = try fetchFinding(id: findingID, sessionID: sessionID)
        try ensureSessionIsEditable(finding.session)
        try saveIfNeeded(backfillHistoricalSnapshots(in: finding.session))

        finding.status = status
        syncNeedsAttention(forAnimalID: animalID(for: finding), in: finding.session)
        try context.save()
    }

    func deleteFinding(sessionID: UUID, findingID: UUID) throws {
        let finding = try fetchFinding(id: findingID, sessionID: sessionID)
        try ensureSessionIsEditable(finding.session)
        try saveIfNeeded(backfillHistoricalSnapshots(in: finding.session))

        let linkedAnimalID = animalID(for: finding)
        let session = finding.session

        syncNeedsAttention(forAnimalID: linkedAnimalID, in: session, excludingFindingID: finding.publicID)
        context.delete(finding)
        try context.save()
    }

    func completeSession(id: UUID) throws {
        guard let session = try fetchSession(id: id) else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
        guard FieldCheckSessionLockRules.isEditable(completedAt: session.completedAt) else { return }

        _ = backfillHistoricalSnapshots(in: session)
        normalizeQuickAnimalTypeCounts(for: session)
        session.completedAt = .now
        try context.save()
    }

    func reopenSession(id: UUID) throws {
        guard let session = try fetchSession(id: id) else {
            throw FieldCheckRepositoryError.sessionNotFound
        }
        try saveIfNeeded(backfillHistoricalSnapshots(in: session))
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
        linkedAnimalID: UUID?,
        session: FieldCheckSession
    ) {
        guard FieldCheckFindingRules.shouldMarkAnimalMissing(for: input.type) else { return }
        guard let linkedAnimalID else { return }
        guard let check = animalCheck(for: linkedAnimalID, in: session) else { return }

        check.missingConfirmedAt = input.recordedAt
        check.countedAt = nil
        normalizeQuickAnimalTypeCounts(for: session)
    }

    private func syncNeedsAttention(
        forAnimalID animalID: UUID?,
        in session: FieldCheckSession?,
        excludingFindingID: UUID? = nil,
        includesNewUnresolvedFinding: Bool = false
    ) {
        guard let animalID, let session else { return }
        guard let check = animalCheck(for: animalID, in: session) else { return }
        check.needsAttention = includesNewUnresolvedFinding
            || hasUnresolvedFinding(
                for: animalID,
                in: session,
                excludingFindingID: excludingFindingID
            )
    }

    private func hasUnresolvedFinding(
        for animalID: UUID,
        in session: FieldCheckSession,
        excludingFindingID: UUID? = nil
    ) -> Bool {
        session.findings.contains { finding in
            finding.publicID != excludingFindingID
                && self.animalID(for: finding) == animalID
                && finding.status != .resolved
        }
    }

    private func animalCheck(for animalID: UUID, in session: FieldCheckSession) -> FieldCheckAnimalCheck? {
        session.animalChecks.first { check in
            self.animalID(for: check) == animalID
        }
    }

    private func animalID(for check: FieldCheckAnimalCheck) -> UUID? {
        check.animalIDSnapshot ?? check.animal?.publicID
    }

    private func animalID(for finding: FieldCheckFinding) -> UUID? {
        finding.animalIDSnapshot ?? finding.animal?.publicID
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
                animalType: check.animalTypeSnapshot,
                wasExpectedAtStart: check.wasExpectedAtStart,
                wasCounted: check.wasCounted,
                isMissing: check.isMissing
            )
        }
    }

    @discardableResult
    private func backfillHistoricalSnapshots(in sessions: [FieldCheckSession]) -> Bool {
        sessions.reduce(false) { didChange, session in
            backfillHistoricalSnapshots(in: session) || didChange
        }
    }

    @discardableResult
    private func backfillHistoricalSnapshots(in session: FieldCheckSession?) -> Bool {
        guard let session else { return false }
        var didChange = false

        if isBlank(session.pastureNameSnapshot), let pastureName = trimmed(session.pasture?.name) {
            session.pastureNameSnapshot = pastureName
            didChange = true
        }

        for check in session.animalChecks {
            didChange = backfillHistoricalSnapshots(for: check) || didChange
        }

        for finding in session.findings {
            didChange = backfillHistoricalSnapshots(for: finding) || didChange
        }

        return didChange
    }

    @discardableResult
    private func backfillHistoricalSnapshots(for findings: [FieldCheckFinding]) -> Bool {
        findings.reduce(false) { didChange, finding in
            let sessionChanged = backfillHistoricalSnapshots(in: finding.session)
            let findingChanged = backfillHistoricalSnapshots(for: finding)
            return sessionChanged || findingChanged || didChange
        }
    }

    @discardableResult
    private func backfillHistoricalSnapshots(for check: FieldCheckAnimalCheck) -> Bool {
        var didChange = false
        let animal = check.animal

        if check.animalIDSnapshot == nil, let animalID = animal?.publicID {
            check.animalIDSnapshot = animalID
            didChange = true
        }
        if isBlank(check.rosterTagNumber), let displayTagNumber = trimmed(animal?.displayTagNumber) {
            check.rosterTagNumber = displayTagNumber
            didChange = true
        }
        if check.rosterTagColorID == nil, let tagColorID = animal?.displayTagColorID {
            check.rosterTagColorID = tagColorID
            didChange = true
        }
        if isBlank(check.damRosterTagNumber), let damDisplayTagNumber = AnimalDisplayTagFormatter.displayTagNumber(for: animal?.damAnimal) {
            check.damRosterTagNumber = damDisplayTagNumber
            didChange = true
        }
        if check.damRosterTagColorID == nil, let damTagColorID = animal?.damAnimal?.displayTagColorID {
            check.damRosterTagColorID = damTagColorID
            didChange = true
        }
        if isBlank(check.animalName), let animalName = trimmed(animal?.name) {
            check.animalName = animalName
            didChange = true
        }
        if !Sex.allCases.map(\.rawValue).contains(check.animalSexRawValue), let sex = animal?.sex {
            check.animalSex = sex
            didChange = true
        }
        if AnimalType(rawValue: check.animalTypeRawValue) == nil {
            check.animalTypeSnapshot = animal?.animalType ?? fallbackAnimalType(for: check.animalSex)
            didChange = true
        }

        return didChange
    }

    @discardableResult
    private func backfillHistoricalSnapshots(for finding: FieldCheckFinding) -> Bool {
        var didChange = false
        let session = finding.session
        let existingAnimalID = animalID(for: finding)
        let check = existingAnimalID.flatMap { id in
            session.flatMap { animalCheck(for: id, in: $0) }
        }
        let animal = finding.animal

        if finding.sessionIDSnapshot == nil, let sessionID = session?.publicID {
            finding.sessionIDSnapshot = sessionID
            didChange = true
        }
        if isBlank(finding.pastureNameSnapshot) {
            if let pastureName = trimmed(session?.pastureNameSnapshot) ?? trimmed(session?.pasture?.name) {
                finding.pastureNameSnapshot = pastureName
                didChange = true
            }
        }
        if finding.animalIDSnapshot == nil, let animalID = animal?.publicID {
            finding.animalIDSnapshot = animalID
            didChange = true
        }
        if isBlank(finding.animalDisplayTagNumberSnapshot) {
            if let tagNumber = trimmed(check?.rosterTagNumber) ?? trimmed(animal?.displayTagNumber) {
                finding.animalDisplayTagNumberSnapshot = tagNumber
                didChange = true
            }
        }
        if finding.animalDisplayTagColorIDSnapshot == nil {
            if let tagColorID = check?.rosterTagColorID ?? animal?.displayTagColorID {
                finding.animalDisplayTagColorIDSnapshot = tagColorID
                didChange = true
            }
        }
        if isBlank(finding.animalNameSnapshot) {
            if let animalName = trimmed(check?.animalName) ?? trimmed(animal?.name) {
                finding.animalNameSnapshot = animalName
                didChange = true
            }
        }

        return didChange
    }

    private func saveIfNeeded(_ shouldSave: Bool) throws {
        guard shouldSave else { return }
        try context.save()
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

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
