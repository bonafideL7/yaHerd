import Foundation

enum FieldCheckMapper {
    static func makeAnimalCheckSnapshot(
        from check: FieldCheckAnimalCheck,
        needsAttention: Bool
    ) -> FieldCheckAnimalCheckSnapshot {
        FieldCheckAnimalCheckSnapshot(
            id: check.publicID,
            animalID: check.animalIDSnapshot ?? check.animal?.publicID,
            displayTagNumber: check.displayTagNumber,
            displayTagColorID: check.rosterTagColorID,
            damDisplayTagNumber: displayTagNumber(from: check.damRosterTagNumber),
            damDisplayTagColorID: check.damRosterTagColorID,
            animalName: check.displayAnimalName,
            animalSex: check.animalSex,
            animalType: check.animalTypeSnapshot,
            wasExpectedAtStart: check.wasExpectedAtStart,
            wasCounted: check.wasCounted,
            needsAttention: needsAttention,
            isMissing: check.isMissing
        )
    }

    static func makeFindingSnapshot(from finding: FieldCheckFinding) -> FieldCheckFindingSnapshot {
        FieldCheckFindingSnapshot(
            id: finding.publicID,
            recordedAt: finding.recordedAt,
            type: finding.type,
            severity: finding.severity,
            status: finding.status,
            note: finding.note,
            animalID: finding.animalIDSnapshot ?? finding.animal?.publicID,
            animalDisplayTagNumber: displayTagNumber(from: finding.animalDisplayTagNumberSnapshot)
                ?? trimmed(finding.animalNameSnapshot),
            animalDisplayTagColorID: finding.animalDisplayTagColorIDSnapshot,
            pastureName: trimmed(finding.pastureNameSnapshot),
            sessionID: finding.sessionIDSnapshot ?? finding.session?.publicID ?? finding.publicID
        )
    }

    static func makeSessionSummary(from session: FieldCheckSession) -> FieldCheckSessionSummary {
        let findings = session.findings.map(makeFindingSnapshot)
        let animalChecks = makeAnimalCheckSnapshots(
            from: session.animalChecks,
            findings: findings
        )
        let openFindingsCount = findings.filter { $0.status != .resolved }.count

        return FieldCheckSessionSummary(
            id: session.publicID,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            pastureID: session.pastureID ?? session.pasture?.publicID,
            pastureName: trimmed(session.pastureNameSnapshot),
            pastureArchivedAt: session.pastureArchivedAt,
            isPastureArchived: isPastureArchived(session),
            expectedHeadCountSnapshot: session.expectedHeadCountSnapshot,
            quickCowCount: session.quickCowCount,
            quickHeiferCount: session.quickHeiferCount,
            quickCalfCount: session.quickCalfCount,
            quickBullCount: session.quickBullCount,
            quickSteerCount: session.quickSteerCount,
            animalChecks: animalChecks,
            openFindingsCount: openFindingsCount
        )
    }

    static func makeSessionDetail(from session: FieldCheckSession) -> FieldCheckSessionDetailSnapshot {
        let findings = session.findings.map(makeFindingSnapshot)
        let animalChecks = makeAnimalCheckSnapshots(
            from: session.animalChecks,
            findings: findings
        )

        return FieldCheckSessionDetailSnapshot(
            id: session.publicID,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            notes: session.notes,
            pastureID: session.pastureID ?? session.pasture?.publicID,
            pastureName: trimmed(session.pastureNameSnapshot),
            pastureArchivedAt: session.pastureArchivedAt,
            isPastureArchived: isPastureArchived(session),
            expectedHeadCountSnapshot: session.expectedHeadCountSnapshot,
            quickCowCount: session.quickCowCount,
            quickHeiferCount: session.quickHeiferCount,
            quickCalfCount: session.quickCalfCount,
            quickBullCount: session.quickBullCount,
            quickSteerCount: session.quickSteerCount,
            animalChecks: animalChecks,
            findings: findings
        )
    }
}

private extension FieldCheckMapper {
    static func makeAnimalCheckSnapshots(
        from checks: [FieldCheckAnimalCheck],
        findings: [FieldCheckFindingSnapshot]
    ) -> [FieldCheckAnimalCheckSnapshot] {
        checks.map { check in
            makeAnimalCheckSnapshot(
                from: check,
                needsAttention: derivedNeedsAttention(for: check, findings: findings)
            )
        }
    }

    static func derivedNeedsAttention(
        for check: FieldCheckAnimalCheck,
        findings: [FieldCheckFindingSnapshot]
    ) -> Bool {
        guard let animalID = check.animalIDSnapshot ?? check.animal?.publicID else { return false }
        return FieldCheckAnimalAttentionRules.shouldNeedAttention(
            animalID: animalID,
            findings: findings
        )
    }

    static func isPastureArchived(_ session: FieldCheckSession) -> Bool {
        if session.pastureArchivedAt != nil { return true }
        guard session.pasture == nil else { return false }
        return session.pastureID != nil || trimmed(session.pastureNameSnapshot) != nil
    }

    static func displayTagNumber(from tagNumber: String) -> String? {
        let display = AnimalDisplayTagFormatter.displayTagNumber(from: tagNumber)
        return display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : display
    }

    static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
