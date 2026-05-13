import Foundation

enum FieldCheckMapper {
    static func makeAnimalCheckSnapshot(from check: FieldCheckAnimalCheck) -> FieldCheckAnimalCheckSnapshot {
        FieldCheckAnimalCheckSnapshot(
            id: check.publicID,
            animalID: check.animal?.publicID,
            displayTagNumber: check.displayTagNumber,
            displayTagColorID: check.animal?.displayTagColorID ?? check.rosterTagColorID,
            damDisplayTagNumber: AnimalDisplayTagFormatter.displayTagNumber(for: check.animal?.damAnimal),
            damDisplayTagColorID: check.animal?.damAnimal?.displayTagColorID,
            animalName: check.animal?.name ?? check.animalName,
            animalSex: check.animal?.sex ?? check.animalSex,
            animalType: check.animal?.animalType ?? fallbackAnimalType(for: check.animalSex),
            wasExpectedAtStart: check.wasExpectedAtStart,
            wasCounted: check.wasCounted,
            needsAttention: check.needsAttention,
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
            animalID: finding.animal?.publicID,
            animalDisplayTagNumber: trimmed(finding.animal?.displayTagNumber) ?? trimmed(finding.animal?.name),
            animalDisplayTagColorID: finding.animal?.displayTagColorID,
            pastureName: finding.session?.pasture?.name,
            sessionID: finding.session?.publicID ?? finding.publicID
        )
    }

    static func makeSessionSummary(from session: FieldCheckSession) -> FieldCheckSessionSummary {
        let animalChecks = session.animalChecks.map(makeAnimalCheckSnapshot)
        let openFindingsCount = session.findings.filter { $0.status != .resolved }.count

        return FieldCheckSessionSummary(
            id: session.publicID,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            pastureID: session.pasture?.publicID,
            pastureName: session.pasture?.name,
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
        FieldCheckSessionDetailSnapshot(
            id: session.publicID,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            notes: session.notes,
            pastureID: session.pasture?.publicID,
            pastureName: session.pasture?.name,
            expectedHeadCountSnapshot: session.expectedHeadCountSnapshot,
            quickCowCount: session.quickCowCount,
            quickHeiferCount: session.quickHeiferCount,
            quickCalfCount: session.quickCalfCount,
            quickBullCount: session.quickBullCount,
            quickSteerCount: session.quickSteerCount,
            animalChecks: session.animalChecks.map(makeAnimalCheckSnapshot),
            findings: session.findings.map(makeFindingSnapshot)
        )
    }
}

private extension FieldCheckMapper {
    static func fallbackAnimalType(for sex: Sex) -> AnimalType {
        switch sex {
        case .female:
            return .cow
        case .male:
            return .bull
        case .unknown:
            return .bull
        }
    }

    static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

}
