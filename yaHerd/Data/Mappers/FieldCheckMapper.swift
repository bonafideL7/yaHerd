import Foundation

enum FieldCheckMapper {
    static func makeAnimalCheckSnapshot(from check: FieldCheckAnimalCheck) -> FieldCheckAnimalCheckSnapshot {
        FieldCheckAnimalCheckSnapshot(
            id: check.publicID,
            animalID: check.animal?.publicID,
            displayTagNumber: check.displayTagNumber,
            displayTagColorID: check.animal?.displayTagColorID ?? check.rosterTagColorID,
            animalName: check.animal?.name ?? check.animalName,
            animalSex: check.animal?.sex ?? check.animalSex,
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
            pastureName: finding.session?.pasture?.name,
            sessionID: finding.session?.publicID ?? UUID(),
            sessionTitle: trimmed(finding.session?.title) ?? finding.session?.pasture?.name ?? "Pasture Check"
        )
    }

    static func makeNewbornSnapshot(from newborn: FieldCheckNewbornDraft) -> FieldCheckNewbornSnapshot {
        FieldCheckNewbornSnapshot(
            id: newborn.publicID,
            recordedAt: newborn.recordedAt,
            sex: newborn.sex,
            isTagged: newborn.isTagged,
            tagNumber: newborn.tagNumber,
            notes: newborn.notes,
            damID: newborn.dam?.publicID,
            damDisplayTagNumber: trimmed(newborn.dam?.displayTagNumber) ?? trimmed(newborn.dam?.name),
            convertedAnimalID: newborn.convertedAnimal?.publicID
        )
    }

    static func makeSessionSummary(from session: FieldCheckSession) -> FieldCheckSessionSummary {
        let animalChecks = session.animalChecks.map(makeAnimalCheckSnapshot)
        let openFindingsCount = session.findings.filter { $0.status != .resolved }.count

        return FieldCheckSessionSummary(
            id: session.publicID,
            title: trimmed(session.title) ?? session.pasture?.name ?? "Pasture Check",
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            pastureID: session.pasture?.publicID,
            pastureName: session.pasture?.name,
            countMode: session.countMode,
            expectedHeadCountSnapshot: session.expectedHeadCountSnapshot,
            quickTaggedCount: session.quickTaggedCount,
            quickUntaggedCount: session.quickUntaggedCount,
            animalChecks: animalChecks,
            openFindingsCount: openFindingsCount
        )
    }

    static func makeSessionDetail(from session: FieldCheckSession) -> FieldCheckSessionDetailSnapshot {
        FieldCheckSessionDetailSnapshot(
            id: session.publicID,
            title: session.title,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            notes: session.notes,
            countMode: session.countMode,
            pastureID: session.pasture?.publicID,
            pastureName: session.pasture?.name,
            expectedHeadCountSnapshot: session.expectedHeadCountSnapshot,
            quickTaggedCount: session.quickTaggedCount,
            quickUntaggedCount: session.quickUntaggedCount,
            animalChecks: session.animalChecks.map(makeAnimalCheckSnapshot),
            findings: session.findings.map(makeFindingSnapshot),
            newborns: session.newbornDrafts.map(makeNewbornSnapshot)
        )
    }
}

private extension FieldCheckMapper {
    static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
