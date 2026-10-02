import Foundation

enum CoreDataFieldCheckMappingError: LocalizedError, Equatable, Sendable {
    case invalidFindingType(findingID: UUID, value: String)
    case invalidFindingSeverity(findingID: UUID, value: String)
    case invalidFindingStatus(findingID: UUID, value: String)
    case invalidAnimalSex(checkID: UUID, value: String)
    case invalidAnimalType(checkID: UUID, value: String)

    var errorDescription: String? {
        switch self {
        case .invalidFindingType:
            return "The Field Check finding contains an invalid persisted type."
        case .invalidFindingSeverity:
            return "The Field Check finding contains an invalid persisted severity."
        case .invalidFindingStatus:
            return "The Field Check finding contains an invalid persisted status."
        case .invalidAnimalSex:
            return "The Field Check roster entry contains an invalid persisted sex."
        case .invalidAnimalType:
            return "The Field Check roster entry contains an invalid persisted animal type."
        }
    }
}

extension FieldCheckMapper {
    static func makeAnimalCheckSnapshot(
        from check: CDFieldCheckAnimalCheck,
        needsAttention: Bool
    ) throws -> FieldCheckAnimalCheckSnapshot {
        guard let sex = Sex(rawValue: check.animalSexRawValueSnapshot) else {
            throw CoreDataFieldCheckMappingError.invalidAnimalSex(
                checkID: check.id,
                value: check.animalSexRawValueSnapshot
            )
        }
        guard let animalType = AnimalType(rawValue: check.animalTypeRawValueSnapshot) else {
            throw CoreDataFieldCheckMappingError.invalidAnimalType(
                checkID: check.id,
                value: check.animalTypeRawValueSnapshot
            )
        }

        return FieldCheckAnimalCheckSnapshot(
            id: check.id,
            animalID: check.animalIDSnapshot,
            displayTagNumber: AnimalDisplayTagFormatter.displayTagNumber(
                from: check.rosterTagNumberSnapshot
            ),
            displayTagColorID: check.rosterTagColorIDSnapshot,
            damDisplayTagNumber: coreDataDisplayTagNumber(from: check.damRosterTagNumberSnapshot),
            damDisplayTagColorID: check.damRosterTagColorIDSnapshot,
            animalName: check.animalNameSnapshot.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            animalSex: sex,
            animalType: animalType,
            wasExpectedAtStart: check.wasExpectedAtStart,
            wasCounted: check.countedAt != nil,
            needsAttention: needsAttention,
            isMissing: check.missingConfirmedAt != nil
        )
    }

    static func makeFindingSnapshot(
        from finding: CDFieldCheckFinding
    ) throws -> FieldCheckFindingSnapshot {
        guard let type = FieldCheckFindingType(rawValue: finding.typeRawValue) else {
            throw CoreDataFieldCheckMappingError.invalidFindingType(
                findingID: finding.id,
                value: finding.typeRawValue
            )
        }
        guard let severity = FieldCheckFindingSeverity(rawValue: finding.severityRawValue) else {
            throw CoreDataFieldCheckMappingError.invalidFindingSeverity(
                findingID: finding.id,
                value: finding.severityRawValue
            )
        }
        guard let status = FieldCheckFindingStatus(rawValue: finding.statusRawValue) else {
            throw CoreDataFieldCheckMappingError.invalidFindingStatus(
                findingID: finding.id,
                value: finding.statusRawValue
            )
        }

        return FieldCheckFindingSnapshot(
            id: finding.id,
            recordedAt: finding.recordedAt,
            type: type,
            severity: severity,
            status: status,
            note: finding.note,
            animalID: finding.animalIDSnapshot,
            animalDisplayTagNumber: coreDataDisplayTagNumber(from: finding.animalDisplayTagNumberSnapshot)
                ?? coreDataTrimmed(finding.animalNameSnapshot),
            animalDisplayTagColorID: finding.animalDisplayTagColorIDSnapshot,
            pastureName: coreDataTrimmed(finding.pastureNameSnapshot),
            sessionID: finding.session.id
        )
    }

    static func makeSessionSummary(
        from session: CDFieldCheckSession
    ) throws -> FieldCheckSessionSummary {
        let findings = try coreDataFindings(session).map {
            try makeFindingSnapshot(from: $0)
        }
        let checks = try coreDataAnimalCheckSnapshots(
            from: coreDataChecks(session),
            findings: findings
        )

        return FieldCheckSessionSummary(
            id: session.id,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            pastureID: session.pastureIDSnapshot,
            pastureName: coreDataTrimmed(session.pastureNameSnapshot),
            pastureArchivedAt: session.pastureArchivedAt,
            isPastureArchived: coreDataIsPastureArchived(session),
            expectedHeadCountSnapshot: Int(session.expectedHeadCountSnapshot),
            quickCowCount: Int(session.quickCowCount),
            quickHeiferCount: Int(session.quickHeiferCount),
            quickCalfCount: Int(session.quickCalfCount),
            quickBullCount: Int(session.quickBullCount),
            quickSteerCount: Int(session.quickSteerCount),
            animalChecks: checks,
            openFindingsCount: findings.filter { $0.status != .resolved }.count
        )
    }

    static func makeSessionDetail(
        from session: CDFieldCheckSession
    ) throws -> FieldCheckSessionDetailSnapshot {
        let findings = try coreDataFindings(session).map {
            try makeFindingSnapshot(from: $0)
        }
        let checks = try coreDataAnimalCheckSnapshots(
            from: coreDataChecks(session),
            findings: findings
        )

        return FieldCheckSessionDetailSnapshot(
            id: session.id,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            notes: session.notes,
            pastureID: session.pastureIDSnapshot,
            pastureName: coreDataTrimmed(session.pastureNameSnapshot),
            pastureArchivedAt: session.pastureArchivedAt,
            isPastureArchived: coreDataIsPastureArchived(session),
            expectedHeadCountSnapshot: Int(session.expectedHeadCountSnapshot),
            quickCowCount: Int(session.quickCowCount),
            quickHeiferCount: Int(session.quickHeiferCount),
            quickCalfCount: Int(session.quickCalfCount),
            quickBullCount: Int(session.quickBullCount),
            quickSteerCount: Int(session.quickSteerCount),
            animalChecks: checks,
            findings: findings
        )
    }
}

private extension FieldCheckMapper {
    static func coreDataAnimalCheckSnapshots(
        from checks: [CDFieldCheckAnimalCheck],
        findings: [FieldCheckFindingSnapshot]
    ) throws -> [FieldCheckAnimalCheckSnapshot] {
        try checks
            .map { check in
                try makeAnimalCheckSnapshot(
                    from: check,
                    needsAttention: FieldCheckAnimalAttentionRules.shouldNeedAttention(
                        animalID: check.animalIDSnapshot,
                        findings: findings
                    )
                )
            }
            .sorted { left, right in
                let comparison = left.displayTagNumber.localizedStandardCompare(
                    right.displayTagNumber
                )
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return left.id.uuidString < right.id.uuidString
            }
    }

    static func coreDataChecks(_ session: CDFieldCheckSession) -> [CDFieldCheckAnimalCheck] {
        (session.animalChecks?.allObjects as? [CDFieldCheckAnimalCheck]) ?? []
    }

    static func coreDataFindings(_ session: CDFieldCheckSession) -> [CDFieldCheckFinding] {
        ((session.findings?.allObjects as? [CDFieldCheckFinding]) ?? [])
            .sorted {
                if $0.recordedAt != $1.recordedAt {
                    return $0.recordedAt > $1.recordedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    static func coreDataIsPastureArchived(_ session: CDFieldCheckSession) -> Bool {
        if session.pastureArchivedAt != nil {
            return true
        }
        return session.pasture == nil
    }

    static func coreDataDisplayTagNumber(from tagNumber: String?) -> String? {
        guard let tagNumber else {
            return nil
        }
        let display = AnimalDisplayTagFormatter.displayTagNumber(from: tagNumber)
        return display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : display
    }

    static func coreDataTrimmed(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
