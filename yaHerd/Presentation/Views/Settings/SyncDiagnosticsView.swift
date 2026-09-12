//
//  SyncDiagnosticsView.swift
//  yaHerd
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
struct SyncDiagnosticsView: View {
    @Environment(\.collaborationDependencies) var collaborationDependencies
    var diagnosticsRepository: (any SyncDiagnosticsRepository)? { collaborationDependencies.diagnosticsRepository }
    var publicIDRepairService: (any PublicIDRepairService)? { collaborationDependencies.publicIDRepairService }
    @Environment(\.appDataAccessMode) var dataAccessMode
    @Environment(\.recoveryModeController) var recoveryModeController
    @Environment(\.modelContext) var modelContext
    @Environment(ApplicationSettings.self) var applicationSettings

    let checker: ICloudAvailabilityChecking
    let schemaChecker: CloudKitSchemaChecking

    @State var launchSnapshot = AppLaunchDiagnostics.snapshot()
    @State var iCloudStatusText = "Checking…"
    @State var counts = SyncDiagnosticsCounts.empty
    @State var countError: String?
    @State var isShowingDeleteConfirmation = false
    @State var isDeletingSyncData = false
    @State var resetResultMessage: String?
    @State var isRunningSchemaCheck = false
    @State var schemaCheckResult: CloudKitSchemaCheckResult?
    @State var publicIDAssessment: PublicIDRepairAssessment?
    @State var publicIDRepairReport: PublicIDRepairReport?
    @State var publicIDRepairError: String?
    @State var publicIDResolutionSelections: [String: String] = [:]
    @State var publicIDIssueSummaries: [String: String] = [:]
    @State var publicIDAnimalDisplays: [String: AnimalSummary] = [:]
    @State var publicIDCandidateLabels: [String: String] = [:]
    @State var publicIDCandidateAnimalDisplays: [String: AnimalSummary] = [:]
    @State var isScanningPublicIDs = false
    @State var isRepairingPublicIDs = false
    @State var isShowingPublicIDRepairConfirmation = false

    init() {
        self.checker = ICloudAvailabilityChecker()
        self.schemaChecker = CloudKitSchemaChecker()
    }

    init(
        checker: ICloudAvailabilityChecking,
        schemaChecker: CloudKitSchemaChecking
    ) {
        self.checker = checker
        self.schemaChecker = schemaChecker
    }

    var body: some View {
        List {
            if dataAccessMode.isRecoveryMode {
                Section("Recovery Mode") {
                    Label("Read-only: changes cannot be saved", systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.red)
                    Button("Export Storage and Attempt Repair") {
                        recoveryModeController?.isPresentingCenter = true
                    }
                }
            }

            Section("Launch State") {
                LabeledContent("Stored Preference", value: applicationSettings.syncMode.displayName)
                LabeledContent("Requested at Launch", value: launchSnapshot.requestedSyncMode.displayName)
                LabeledContent("Actual Launch", value: launchSnapshot.actualStorageMode.displayName)
                LabeledContent("CloudKit Opened", value: launchSnapshot.cloudKitOpened ? "Yes" : "No")
            }

            Section("iCloud") {
                LabeledContent("Account Status", value: iCloudStatusText)
                LabeledContent("SwiftData CloudKit", value: swiftDataCloudKitDescription)
                LabeledContent("CloudKit Container", value: ModelContainerFactory.cloudKitContainerIdentifier)
                LabeledContent("Store", value: activeStoreDescription)
            }

            Section("App") {
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "Unknown")
                LabeledContent("Build Configuration", value: buildConfiguration)
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                LabeledContent("iCloud Environment", value: iCloudEnvironmentDescription)
            }

            Section("Local Data Counts") {
                if let countError {
                    Text(countError)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    LabeledContent("Herds", value: counts.herds.formatted())
                    LabeledContent("Animals", value: counts.animals.formatted())
                    LabeledContent("Pastures", value: counts.pastures.formatted())
                    LabeledContent("Pasture Groups", value: counts.pastureGroups.formatted())
                    LabeledContent("Health Records", value: counts.healthRecords.formatted())
                    LabeledContent("Pregnancy Checks", value: counts.pregnancyChecks.formatted())
                    LabeledContent("Movement Records", value: counts.movementRecords.formatted())
                    LabeledContent("Status Records", value: counts.statusRecords.formatted())
                    LabeledContent("Working Sessions", value: counts.workingSessions.formatted())
                    LabeledContent("Working Queue Items", value: counts.workingQueueItems.formatted())
                    LabeledContent("Working Treatments", value: counts.workingTreatmentRecords.formatted())
                    LabeledContent("Field Check Sessions", value: counts.fieldCheckSessions.formatted())
                    LabeledContent("Field Check Animal Checks", value: counts.fieldCheckAnimalChecks.formatted())
                    LabeledContent("Field Check Findings", value: counts.fieldCheckFindings.formatted())
                }
            }

            Section("Public ID Integrity") {
                Button {
                    scanPublicIDs()
                } label: {
                    if isScanningPublicIDs {
                        Label("Scanning Public IDs…", systemImage: "hourglass")
                    } else {
                        Label("Scan for Duplicate Public IDs", systemImage: "magnifyingglass")
                    }
                }
                .disabled(isScanningPublicIDs || isRepairingPublicIDs)

                Text("Checks every entity type used by herd sharing. The scan does not change data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let assessment = publicIDAssessment {
                    LabeledContent("Records Scanned", value: assessment.totalScannedRecordCount.formatted())
                    LabeledContent("Duplicate Groups", value: assessment.duplicateGroupCount.formatted())
                    LabeledContent("Records Requiring New IDs", value: assessment.duplicateRecordCount.formatted())
                    LabeledContent("Choices Required", value: assessment.unresolvedReferences.count.formatted())

                    if assessment.requiresBridgeConvergence {
                        Label("Repair recovery or shared-data convergence must be completed", systemImage: "arrow.triangle.2.circlepath.icloud")
                            .foregroundStyle(.orange)
                        Text("A durable public-ID repair journal is pending. Normal changes and synchronization remain blocked until the local repair state and shared-data export are verified using the original storage mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if assessment.hasBlockingIssues {
                        Label("Resolve every repair blocker", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)

                        ForEach(assessment.unresolvedReferences) { issue in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(publicIDIssueHeading(issue))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(publicIDIssueSummary(issue))
                                    .font(.subheadline.weight(.semibold))

                                if let animal = publicIDAnimalDisplays[issue.id] {
                                    publicIDAnimalIdentityCard(animal)
                                }

                                Text(publicIDIssueGuidance(issue))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if issue.candidates.isEmpty {
                                    if issue.kind == .indeterminateLocalRepairRecovery {
                                        Text("No safe automatic or backup recovery choice is available for this evidence. Repair remains blocked; yaHerd will not infer deletion or choose a record automatically.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("There is not enough information to make a safe choice yet. yaHerd will not guess which record should receive an identity.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(publicIDPickerTitle(issue))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)

                                        ForEach(issue.candidates) { candidate in
                                            publicIDCandidateSelectionRow(candidate, for: issue)
                                        }
                                    }
                                    .accessibilityElement(children: .contain)
                                }

                                DisclosureGroup("Technical details") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        LabeledContent("Record type", value: issue.entityType.displayName)
                                        LabeledContent("Conflict field", value: publicIDHumanFieldName(issue.fieldName))
                                        Text("Historical public ID")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Text(issue.referencedPublicID.uuidString)
                                            .font(.caption2.monospaced())
                                            .textSelection(.enabled)
                                        Text(issue.reason)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                        if let selectedCandidate = selectedCandidate(for: issue) {
                                            Text("Selected resulting public ID")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            Text(selectedCandidate.resultingPublicID.uuidString)
                                                .font(.caption2.monospaced())
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                                .font(.caption)
                            }
                            .padding(.vertical, 6)
                        }
                    }

                    if assessment.hasRepairWork {
                        let hasCompleteSelections = hasCompleteReferenceSelections(for: assessment)

                        Button {
                            isShowingPublicIDRepairConfirmation = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: publicIDRepairActionIconName(for: assessment))
                                    .symbolRenderingMode(.monochrome)
                                Text(publicIDRepairActionTitle(for: assessment))
                            }
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(
                            isRepairingPublicIDs
                                || isScanningPublicIDs
                                || dataAccessMode.isRecoveryMode
                                || !hasCompleteSelections
                        )
                        .confirmationDialog(
                            publicIDRepairConfirmationTitle,
                            isPresented: $isShowingPublicIDRepairConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button(
                                publicIDRepairConfirmationButtonTitle,
                                role: publicIDRepairConfirmationRole
                            ) {
                                repairPublicIDs()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text(publicIDRepairConfirmationMessage)
                        }
                    } else {
                        Label("No duplicate public IDs found", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if let publicIDRepairReport {
                    Text(publicIDRepairReport.userReadableSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let publicIDRepairError {
                    Text(publicIDRepairError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("CloudKit Schema Check") {
                Button {
                    runSchemaCheck()
                } label: {
                    if isRunningSchemaCheck {
                        Label("Running Schema Check…", systemImage: "hourglass")
                    } else {
                        Label("Run Schema Check", systemImage: "checkmark.icloud")
                    }
                }
                .disabled(isRunningSchemaCheck || dataAccessMode.isRecoveryMode)

                Text("Writes, reads, and deletes a small diagnostic CloudKit record in the active CloudKit environment. In TestFlight, this should be Production.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let schemaCheckResult {
                    LabeledContent("Environment", value: schemaCheckResult.environmentDescription)
                    LabeledContent("Result", value: schemaCheckResult.passed ? "Passed" : "Failed")
                    Text(schemaCheckResult.message)
                        .font(.caption)
                        .foregroundStyle(schemaCheckResult.passed ? Color.secondary : Color.red)
                }
            }

            Section("Danger Zone") {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    if isDeletingSyncData {
                        Label("Deleting Sync Data…", systemImage: "hourglass")
                    } else {
                        Label("Delete iCloud Sync Data", systemImage: "trash")
                    }
                }
                .disabled(isDeletingSyncData || dataAccessMode.isRecoveryMode)

                Text("Deletes yaHerd CloudKit herd data zones and synced app settings from iCloud in the active environment. Local data on this device is not deleted. Sync Mode switches back to Local Only and an app restart is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let resetResultMessage {
                    Text(resetResultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let startupError = launchSnapshot.startupError, !startupError.isEmpty {
                Section("Last Startup Error") {
                    Text(startupError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("What This Means") {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sync Diagnostics")
        .task {
            await refreshDiagnostics()
            if publicIDAssessment == nil,
               publicIDRepairService != nil,
               !dataAccessMode.isRecoveryMode {
                scanPublicIDs()
            }
        }
        .confirmationDialog(
            "Delete iCloud Sync Data?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete iCloud Sync Data", role: .destructive) {
                deleteSyncData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is for development testing. It deletes yaHerd CloudKit herd data zones and synced app settings from iCloud. Local data on this device is not deleted. Restart yaHerd afterward.")
        }
    }

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
        let targetID = candidate.resultingPublicID
        let animal: Animal?

        switch issue.entityType {
        case .movement:
            var descriptor = FetchDescriptor<MovementRecord>(
                predicate: #Predicate { $0.publicID == targetID }
            )
            descriptor.fetchLimit = 1
            animal = (try? modelContext.fetch(descriptor).first)?.animal

        case .pregnancyCheck:
            var descriptor = FetchDescriptor<PregnancyCheck>(
                predicate: #Predicate { $0.publicID == targetID }
            )
            descriptor.fetchLimit = 1
            animal = (try? modelContext.fetch(descriptor).first)?.animal

        case .statusRecord:
            var descriptor = FetchDescriptor<StatusRecord>(
                predicate: #Predicate { $0.publicID == targetID }
            )
            descriptor.fetchLimit = 1
            animal = (try? modelContext.fetch(descriptor).first)?.animal

        default:
            animal = nil
        }

        guard let animal else { return nil }
        return AnimalMapper.makeSummary(from: animal)
    }

    func publicIDPreparedCandidateLabel(
        _ candidate: PublicIDRepairResolutionCandidate,
        for issue: PublicIDRepairUnresolvedReference
    ) -> String {
        if candidate.stableRecordIdentifier.hasPrefix("bridge-canonical-restore|")
            || candidate.stableRecordIdentifier.hasPrefix("bridge-canonical-remove|") {
            return candidate.recordDescription
        }

        switch issue.entityType {
        case .movement:
            let targetID = candidate.resultingPublicID
            var descriptor = FetchDescriptor<MovementRecord>(
                predicate: #Predicate { $0.publicID == targetID }
            )
            descriptor.fetchLimit = 1
            if let movement = try? modelContext.fetch(descriptor).first {
                let from = publicIDNonempty(movement.fromPasture) ?? "Unknown pasture"
                let to = publicIDNonempty(movement.toPasture) ?? "Unknown pasture"
                return "\(publicIDAnimalLabel(movement.animal)) • \(publicIDDate(movement.date)) • \(from) → \(to)"
            }

        case .pregnancyCheck:
            let targetID = candidate.resultingPublicID
            var descriptor = FetchDescriptor<PregnancyCheck>(
                predicate: #Predicate { $0.publicID == targetID }
            )
            descriptor.fetchLimit = 1
            if let check = try? modelContext.fetch(descriptor).first {
                var parts = [
                    publicIDAnimalLabel(check.animal),
                    publicIDDate(check.date),
                    publicIDHumanEnumValue(check.result.rawValue),
                ]
                if let days = check.estimatedDaysPregnant {
                    parts.append("\(days) days pregnant")
                }
                if let dueDate = check.dueDate {
                    parts.append("Due \(publicIDDate(dueDate))")
                }
                if let technician = publicIDNonempty(check.technician) {
                    parts.append("Technician: \(technician)")
                }
                return parts.joined(separator: " • ")
            }

        case .statusRecord:
            let targetID = candidate.resultingPublicID
            var descriptor = FetchDescriptor<StatusRecord>(
                predicate: #Predicate { $0.publicID == targetID }
            )
            descriptor.fetchLimit = 1
            if let status = try? modelContext.fetch(descriptor).first {
                return "\(publicIDAnimalLabel(status.animal)) • \(publicIDDate(status.date)) • \(publicIDHumanEnumValue(status.oldStatus.rawValue)) → \(publicIDHumanEnumValue(status.newStatus.rawValue))"
            }

        default:
            break
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
           let animal = publicIDAnimal(publicID: id) {
            return AnimalMapper.makeSummary(from: animal)
        }

        if let animal = publicIDAnimalFromRepairCandidates(for: issue) {
            return AnimalMapper.makeSummary(from: animal)
        }

        guard let tagNumber = publicIDSharedAnimalTagNumber(in: issue.recordDescription),
              let animal = publicIDUniqueAnimal(tagNumber: tagNumber) else {
            return nil
        }
        return AnimalMapper.makeSummary(from: animal)
    }

    func publicIDAnimal(publicID: UUID) -> Animal? {
        var descriptor = FetchDescriptor<Animal>(
            predicate: #Predicate { $0.publicID == publicID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
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

    func publicIDAnimalFromRepairCandidates(for issue: PublicIDRepairUnresolvedReference) -> Animal? {
        var animalsByPublicID: [UUID: Animal] = [:]

        for candidate in issue.candidates {
            let candidateID = candidate.resultingPublicID
            let animal: Animal?

            switch issue.entityType {
            case .movement:
                var descriptor = FetchDescriptor<MovementRecord>(
                    predicate: #Predicate { $0.publicID == candidateID }
                )
                descriptor.fetchLimit = 1
                animal = (try? modelContext.fetch(descriptor).first)?.animal

            case .pregnancyCheck:
                var descriptor = FetchDescriptor<PregnancyCheck>(
                    predicate: #Predicate { $0.publicID == candidateID }
                )
                descriptor.fetchLimit = 1
                animal = (try? modelContext.fetch(descriptor).first)?.animal

            case .statusRecord:
                var descriptor = FetchDescriptor<StatusRecord>(
                    predicate: #Predicate { $0.publicID == candidateID }
                )
                descriptor.fetchLimit = 1
                animal = (try? modelContext.fetch(descriptor).first)?.animal

            default:
                animal = nil
            }

            if let animal {
                animalsByPublicID[animal.publicID] = animal
            }
        }

        guard !animalsByPublicID.isEmpty else { return nil }

        if let tagNumber = publicIDSharedAnimalTagNumber(in: issue.recordDescription) {
            let taggedAnimals = animalsByPublicID.values.filter {
                publicIDAnimal($0, hasTagNumber: tagNumber)
            }
            if taggedAnimals.count == 1 {
                return taggedAnimals[0]
            }
        }

        guard animalsByPublicID.count == 1 else { return nil }
        return animalsByPublicID.values.first
    }

    func publicIDAnimal(_ animal: Animal, hasTagNumber tagNumber: String) -> Bool {
        let normalizedTag = tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTag.isEmpty else { return false }

        if animal.tagNumber.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedTag {
            return true
        }
        return animal.tags.contains { tag in
            tag.normalizedNumber == normalizedTag
        }
    }

    func publicIDUniqueAnimal(tagNumber: String) -> Animal? {
        var animalDescriptor = FetchDescriptor<Animal>(
            predicate: #Predicate { $0.tagNumber == tagNumber }
        )
        animalDescriptor.fetchLimit = 2
        if let matches = try? modelContext.fetch(animalDescriptor),
           matches.count == 1 {
            return matches[0]
        }

        var tagDescriptor = FetchDescriptor<AnimalTag>(
            predicate: #Predicate { $0.number == tagNumber }
        )
        tagDescriptor.fetchLimit = 8
        guard let tagMatches = try? modelContext.fetch(tagDescriptor) else {
            return nil
        }
        let activePrimaryAnimals = tagMatches
            .filter { $0.isPrimary && $0.isActive }
            .compactMap(\.animal)
        let uniqueByPublicID = Dictionary(grouping: activePrimaryAnimals, by: \.publicID)
        guard uniqueByPublicID.count == 1 else {
            return nil
        }
        return uniqueByPublicID.values.first?.first
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
        if !tag.isEmpty && tag != "UT" && !name.isEmpty {
            return "Tag \(tag) — \(name)"
        }
        if !tag.isEmpty && tag != "UT" {
            return "Tag \(tag)"
        }
        if !name.isEmpty {
            return name
        }
        return "Untagged animal"
    }

    func publicIDAnimalLabel(publicID rawID: String) -> String {
        guard let id = UUID(uuidString: rawID),
              let animal = publicIDAnimal(publicID: id) else {
            return "Unknown animal"
        }
        return publicIDAnimalLabel(animal)
    }

    func publicIDAnimalLabel(_ animal: Animal?) -> String {
        guard let animal else { return "Unknown animal" }
        let tag = animal.tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = animal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty && !name.isEmpty {
            return "Tag \(tag) — \(name)"
        }
        if !tag.isEmpty {
            return "Tag \(tag)"
        }
        if !name.isEmpty {
            return name
        }
        return "Untagged animal"
    }
}
