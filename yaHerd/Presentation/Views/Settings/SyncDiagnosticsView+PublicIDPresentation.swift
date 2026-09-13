import Foundation
import SwiftUI

extension SyncDiagnosticsView {
    func publicIDRepairActionTitle(for assessment: PublicIDRepairAssessment) -> String {
        if isRepairingPublicIDs {
            return assessment.requiresBridgeConvergence && !assessment.hasDuplicates
                ? "Finishing Convergence…"
                : "Repairing Duplicate IDs…"
        }
        if assessment.requiresBridgeConvergence && !assessment.hasDuplicates {
            return "Finish Shared-Data Convergence"
        }
        return "Back Up and Repair Duplicate IDs"
    }

    func publicIDRepairActionIconName(for assessment: PublicIDRepairAssessment) -> String {
        if isRepairingPublicIDs {
            return "hourglass"
        }
        if assessment.requiresBridgeConvergence && !assessment.hasDuplicates {
            return "arrow.triangle.2.circlepath"
        }
        return "wrench.and.screwdriver"
    }

    func publicIDIssueHeading(_ issue: PublicIDRepairUnresolvedReference) -> String {
        switch issue.kind {
        case .canonicalRecord:
            issue.fieldName == "deletionTargetPublicID" ? "Shared deletion to resolve" : "Shared record to resolve"
        case .lookupReference, .treatmentReference, .bridgeRecordOwner:
            "Shared reference to resolve"
        case .preparedHerdRecovery:
            "Shared Herd recovery decision"
        case .indeterminateLocalRepairRecovery:
            "Repair recovery decision"
        }
    }

    func publicIDPickerTitle(_ issue: PublicIDRepairUnresolvedReference) -> String {
        switch issue.kind {
        case .canonicalRecord:
            "Matching local record"
        case .lookupReference, .treatmentReference, .bridgeRecordOwner:
            "Referenced local record"
        case .preparedHerdRecovery, .indeterminateLocalRepairRecovery:
            "Recovery action"
        }
    }

    func publicIDIssueGuidance(_ issue: PublicIDRepairUnresolvedReference) -> String {
        switch issue.kind {
        case .canonicalRecord:
            if issue.fieldName == "deletionTargetPublicID" {
                return "This deletion was created while more than one physical record used the same old identity. Choose the local record that the deletion was intended to remove."
            }
            return "This shared record still uses an old public ID that belonged to multiple local records. Compare the shared record above with the local choices below. Choose the matching local record, restore the shared record if it is missing locally, or remove only the shared copy if it is genuinely obsolete."
        case .lookupReference, .treatmentReference:
            return "This shared record points to an identity that was duplicated locally. Choose the local record that this reference actually belongs to."
        case .bridgeRecordOwner:
            return "Choose the record that actually owns this shared bridge reference. yaHerd will not infer ownership from a duplicated identity."
        case .preparedHerdRecovery:
            return "Choose how to resolve this prepared shared Herd using the verified bridge state shown here."
        case .indeterminateLocalRepairRecovery:
            return "The previous repair stopped after a durable write boundary. Choose the recovery action that matches the evidence shown here."
        }
    }

    func publicIDIssueSummary(_ issue: PublicIDRepairUnresolvedReference) -> String {
        publicIDIssueSummaries[issue.id] ?? publicIDReadableRawDescription(issue.recordDescription)
    }

    func publicIDCandidateLabel(
        _ candidate: PublicIDRepairResolutionCandidate,
        for issue: PublicIDRepairUnresolvedReference
    ) -> String {
        publicIDCandidateLabels[publicIDCandidateCacheKey(issue: issue, candidate: candidate)]
            ?? publicIDReadableRawDescription(candidate.recordDescription)
    }

    @ViewBuilder
    func publicIDCandidateSelectionRow(
        _ candidate: PublicIDRepairResolutionCandidate,
        for issue: PublicIDRepairUnresolvedReference
    ) -> some View {
        let cacheKey = publicIDCandidateCacheKey(issue: issue, candidate: candidate)
        let isSelected = publicIDResolutionSelections[issue.id] == candidate.stableRecordIdentifier

        Button {
            publicIDResolutionSelections[issue.id] = candidate.stableRecordIdentifier
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.top, 4)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    if let animal = publicIDCandidateAnimalDisplays[cacheKey] {
                        AnimalListRowContent(animal: animal)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(publicIDCandidateLabel(candidate, for: issue))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(publicIDCandidateLabel(candidate, for: issue))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.16), lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(publicIDCandidateLabel(candidate, for: issue))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    func rebuildPublicIDDisplayCache(for assessment: PublicIDRepairAssessment) {
        var summaries: [String: String] = [:]
        var animals: [String: AnimalSummary] = [:]
        var candidateLabels: [String: String] = [:]
        var candidateAnimals: [String: AnimalSummary] = [:]

        for issue in assessment.unresolvedReferences {
            let animalDisplay = publicIDPreparedAnimalDisplay(for: issue)
            if let animalDisplay {
                animals[issue.id] = animalDisplay
            }
            summaries[issue.id] = publicIDPreparedIssueSummary(
                issue,
                animalLabel: animalDisplay.map(publicIDAnimalLabel)
            )

            for candidate in issue.candidates {
                let cacheKey = publicIDCandidateCacheKey(issue: issue, candidate: candidate)
                candidateLabels[cacheKey] = publicIDPreparedCandidateLabel(candidate, for: issue)
                if let animal = publicIDPreparedCandidateAnimal(candidate, for: issue) {
                    candidateAnimals[cacheKey] = animal
                }
            }
        }

        publicIDIssueSummaries = summaries
        publicIDAnimalDisplays = animals
        publicIDCandidateLabels = candidateLabels
        publicIDCandidateAnimalDisplays = candidateAnimals
    }

    func clearPublicIDDisplayCache() {
        publicIDIssueSummaries = [:]
        publicIDAnimalDisplays = [:]
        publicIDCandidateLabels = [:]
        publicIDCandidateAnimalDisplays = [:]
    }

    func publicIDCandidateCacheKey(
        issue: PublicIDRepairUnresolvedReference,
        candidate: PublicIDRepairResolutionCandidate
    ) -> String {
        "\(issue.id)|\(candidate.stableRecordIdentifier)"
    }

    func publicIDPreparedIssueSummary(
        _ issue: PublicIDRepairUnresolvedReference,
        animalLabel: String?
    ) -> String {
        switch issue.entityType {
        case .movement:
            if issue.recordDescription.hasPrefix("Shared movement:") {
                return issue.recordDescription
            }
            return publicIDParsedMovementSummary(issue.recordDescription, animalLabel: animalLabel)
                ?? publicIDReadableRawDescription(issue.recordDescription)
        case .pregnancyCheck:
            if issue.recordDescription.hasPrefix("Shared pregnancy check:") {
                return issue.recordDescription
            }
            return publicIDParsedPregnancySummary(issue.recordDescription, animalLabel: animalLabel)
                ?? publicIDReadableRawDescription(issue.recordDescription)
        case .statusRecord:
            return publicIDParsedStatusSummary(issue.recordDescription, animalLabel: animalLabel)
                ?? publicIDReadableRawDescription(issue.recordDescription)
        default:
            return publicIDReadableRawDescription(issue.recordDescription)
        }
    }

    func publicIDPreparedCandidateAnimal(
        _ candidate: PublicIDRepairResolutionCandidate,
        for issue: PublicIDRepairUnresolvedReference
    ) -> AnimalSummary? {
        publicIDRecord(
            entityType: issue.entityType,
            publicID: candidate.resultingPublicID
        )?.animal?.summary
    }

    func publicIDPreparedCandidateLabel(
        _ candidate: PublicIDRepairResolutionCandidate,
        for issue: PublicIDRepairUnresolvedReference
    ) -> String {
        if candidate.stableRecordIdentifier.hasPrefix("bridge-canonical-restore|")
            || candidate.stableRecordIdentifier.hasPrefix("bridge-canonical-remove|") {
            return candidate.recordDescription
        }

        if let record = publicIDRecord(
            entityType: issue.entityType,
            publicID: candidate.resultingPublicID
        ) {
            let animalLabel = record.animal.map { publicIDAnimalLabel($0.summary) } ?? "Unknown animal"

            switch issue.entityType {
            case .movement:
                if let date = record.date {
                    let from = publicIDNonempty(record.fromPasture) ?? "Unknown pasture"
                    let to = publicIDNonempty(record.toPasture) ?? "Unknown pasture"
                    return "\(animalLabel) • \(publicIDDate(date)) • \(from) → \(to)"
                }

            case .pregnancyCheck:
                if let date = record.date, let result = record.resultRawValue {
                    var parts = [
                        animalLabel,
                        publicIDDate(date),
                        publicIDHumanEnumValue(result),
                    ]
                    if let days = record.estimatedDaysPregnant {
                        parts.append("\(days) days pregnant")
                    }
                    if let dueDate = record.dueDate {
                        parts.append("Due \(publicIDDate(dueDate))")
                    }
                    if let technician = publicIDNonempty(record.technician) {
                        parts.append("Technician: \(technician)")
                    }
                    return parts.joined(separator: " • ")
                }

            case .statusRecord:
                if let date = record.date,
                   let oldStatus = record.oldStatusRawValue,
                   let newStatus = record.newStatusRawValue {
                    return "\(animalLabel) • \(publicIDDate(date)) • \(publicIDHumanEnumValue(oldStatus)) → \(publicIDHumanEnumValue(newStatus))"
                }

            default:
                break
            }
        }

        let readableDetail = publicIDReadableTechnicalDetail(candidate.detail)
        if !readableDetail.isEmpty {
            return readableDetail
        }
        return publicIDReadableRawDescription(candidate.recordDescription)
    }

    func publicIDParsedMovementSummary(_ text: String, animalLabel: String?) -> String? {
        guard publicIDRawField("animalPublicID", in: text) != nil,
              let date = publicIDRawField("date", in: text) else {
            return nil
        }
        let animal = animalLabel ?? "Unknown animal"
        let from = publicIDRawField("fromPasture", in: text) ?? "Unknown pasture"
        let to = publicIDRawField("toPasture", in: text) ?? "Unknown pasture"
        return "Shared movement: \(animal) • \(publicIDCleanDateText(date)) • \(from) → \(to)"
    }

    func publicIDParsedPregnancySummary(_ text: String, animalLabel: String?) -> String? {
        guard publicIDRawField("animalPublicID", in: text) != nil,
              let date = publicIDRawField("date", in: text) else {
            return nil
        }
        let result = publicIDRawField("resultRawValue", in: text)
            ?? publicIDRawField("result", in: text)
            ?? "unknown"
        var parts = [
            animalLabel ?? "Unknown animal",
            publicIDCleanDateText(date),
            publicIDHumanEnumValue(result),
        ]
        if let days = publicIDRawField("estimatedDaysPregnant", in: text) {
            parts.append("\(days) days pregnant")
        }
        if let dueDate = publicIDRawField("dueDate", in: text) {
            parts.append("Due \(publicIDCleanDateText(dueDate))")
        }
        return "Shared pregnancy check: \(parts.joined(separator: " • "))"
    }

    func publicIDParsedStatusSummary(_ text: String, animalLabel: String?) -> String? {
        guard publicIDRawField("animalPublicID", in: text) != nil,
              let date = publicIDRawField("date", in: text) else {
            return nil
        }
        let oldStatus = publicIDRawField("oldStatusRawValue", in: text)
            ?? publicIDRawField("oldStatus", in: text)
            ?? "unknown"
        let newStatus = publicIDRawField("newStatusRawValue", in: text)
            ?? publicIDRawField("newStatus", in: text)
            ?? "unknown"
        return "Shared status change: \(animalLabel ?? "Unknown animal") • \(publicIDCleanDateText(date)) • \(publicIDHumanEnumValue(oldStatus)) → \(publicIDHumanEnumValue(newStatus))"
    }

    func publicIDRawField(_ key: String, in text: String) -> String? {
        guard let keyRange = text.range(of: "\(key):") else { return nil }
        let remainder = text[keyRange.upperBound...]
        let end = remainder.range(of: " • ")?.lowerBound ?? remainder.endIndex
        let value = String(remainder[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func publicIDReadableRawDescription(_ text: String) -> String {
        var output = text
        let replacements: [(String, String)] = [
            ("animalPublicID:", "Animal:"),
            ("date:", "Date:"),
            ("newStatusRawValue:", "New status:"),
            ("oldStatusRawValue:", "Previous status:"),
            ("resultRawValue:", "Result:"),
            ("estimatedDaysPregnant:", "Estimated days pregnant:"),
            ("dueDate:", "Due date:"),
            ("fromPasture:", "From:"),
            ("toPasture:", "To:"),
        ]
        for (raw, readable) in replacements {
            output = output.replacingOccurrences(of: raw, with: readable)
        }
        return output
    }

    func publicIDReadableTechnicalDetail(_ detail: String) -> String {
        let parts = detail
            .components(separatedBy: " • ")
            .compactMap { rawPart -> String? in
                let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !part.isEmpty else { return nil }
                guard let separator = part.firstIndex(of: ":") else {
                    return publicIDCleanDateText(part)
                }
                let rawKey = String(part[..<separator])
                let rawValue = String(part[part.index(after: separator)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if rawKey.lowercased().contains("publicid") {
                    if rawKey.lowercased().contains("animal") {
                        return "Animal: \(publicIDAnimalLabel(publicID: rawValue))"
                    }
                    return nil
                }

                let value = rawKey.hasSuffix("RawValue")
                    ? publicIDHumanEnumValue(rawValue)
                    : publicIDCleanDateText(rawValue)
                return "\(publicIDHumanFieldName(rawKey)): \(value)"
            }
        return parts.joined(separator: " • ")
    }

    func publicIDHumanFieldName(_ raw: String) -> String {
        let explicit: [String: String] = [
            "publicID": "Public ID",
            "deletionTargetPublicID": "Deleted record",
            "animalPublicID": "Animal",
            "sireAnimalPublicID": "Sire",
            "workingSessionPublicID": "Working session",
            "sessionPublicID": "Session",
            "pasturePublicID": "Pasture",
            "sourcePasturePublicID": "Source pasture",
            "fromPasture": "From",
            "toPasture": "To",
            "oldStatusRawValue": "Previous status",
            "newStatusRawValue": "New status",
            "resultRawValue": "Result",
            "estimatedDaysPregnant": "Estimated days pregnant",
            "dueDate": "Due date",
        ]
        if let explicitName = explicit[raw] {
            return explicitName
        }

        var words = ""
        for scalar in raw.unicodeScalars {
            let character = Character(String(scalar))
            if character.isUppercase, !words.isEmpty {
                words.append(" ")
            }
            words.append(character)
        }
        words = words
            .replacingOccurrences(of: "Raw Value", with: "")
            .replacingOccurrences(of: "Public ID", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return raw }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    func publicIDHumanEnumValue(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    func publicIDCleanDateText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: ", 00:00", with: "")
            .replacingOccurrences(of: ", 12:00 AM", with: "")
    }

    func publicIDDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    func publicIDNonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func publicIDPreparedAnimalDisplay(for issue: PublicIDRepairUnresolvedReference) -> AnimalSummary? {
        if let rawID = publicIDRawField("animalPublicID", in: issue.recordDescription),
           let id = UUID(uuidString: rawID),
           let animal = publicIDAnimalIdentity(publicID: id) {
            return animal.summary
        }

        if let animal = publicIDAnimalFromRepairCandidates(for: issue) {
            return animal.summary
        }

        guard let tagNumber = publicIDSharedAnimalTagNumber(in: issue.recordDescription),
              let animal = publicIDUniqueAnimalIdentity(tagNumber: tagNumber) else {
            return nil
        }
        return animal.summary
    }

    func publicIDSharedAnimalTagNumber(in text: String) -> String? {
        guard text.hasPrefix("Shared "),
              let markerRange = text.range(of: ": Tag ") else {
            return nil
        }
        let remainder = text[markerRange.upperBound...]
        let end = remainder.range(of: " • ")?.lowerBound ?? remainder.endIndex
        let tag = String(remainder[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? nil : tag
    }

    func publicIDAnimalFromRepairCandidates(
        for issue: PublicIDRepairUnresolvedReference
    ) -> SyncDiagnosticsAnimalIdentity? {
        var animalsByPublicID: [UUID: SyncDiagnosticsAnimalIdentity] = [:]

        for candidate in issue.candidates {
            guard let animal = publicIDRecord(
                entityType: issue.entityType,
                publicID: candidate.resultingPublicID
            )?.animal else {
                continue
            }
            animalsByPublicID[animal.summary.id] = animal
        }

        guard !animalsByPublicID.isEmpty else { return nil }

        if let tagNumber = publicIDSharedAnimalTagNumber(in: issue.recordDescription) {
            let normalizedTag = tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let taggedAnimals = animalsByPublicID.values.filter {
                $0.tagNumbers.contains(normalizedTag)
            }
            if taggedAnimals.count == 1 {
                return taggedAnimals[0]
            }
        }

        guard animalsByPublicID.count == 1 else { return nil }
        return animalsByPublicID.values.first
    }

    @ViewBuilder
    func publicIDAnimalIdentityCard(_ animal: AnimalSummary) -> some View {
        GroupBox("Animal referenced by shared record") {
            AnimalListRowContent(animal: animal)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }

    func publicIDAnimalLabel(_ animal: AnimalSummary) -> String {
        let tag = animal.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = animal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let colorName = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID).name

        if !tag.isEmpty && tag != "UT" && !name.isEmpty {
            return "\(colorName) tag \(tag) — \(name)"
        }
        if !tag.isEmpty && tag != "UT" {
            return "\(colorName) tag \(tag)"
        }
        if !name.isEmpty {
            return name
        }
        return "Untagged animal"
    }

    func publicIDAnimalLabel(publicID rawID: String) -> String {
        guard let id = UUID(uuidString: rawID),
              let animal = publicIDAnimalIdentity(publicID: id) else {
            return "Unknown animal"
        }
        return publicIDAnimalLabel(animal.summary)
    }

    private func publicIDAnimalIdentity(publicID: UUID) -> SyncDiagnosticsAnimalIdentity? {
        guard let diagnosticsRepository else { return nil }
        return try? diagnosticsRepository.fetchAnimalIdentity(publicID: publicID)
    }

    private func publicIDUniqueAnimalIdentity(tagNumber: String) -> SyncDiagnosticsAnimalIdentity? {
        guard let diagnosticsRepository else { return nil }
        return try? diagnosticsRepository.fetchUniqueAnimalIdentity(tagNumber: tagNumber)
    }

    private func publicIDRecord(
        entityType: PublicIDRepairEntityType,
        publicID: UUID
    ) -> SyncDiagnosticsPublicIDRecord? {
        guard let diagnosticsRepository else { return nil }
        return try? diagnosticsRepository.fetchPublicIDRecord(
            entityType: entityType,
            publicID: publicID
        )
    }
}
