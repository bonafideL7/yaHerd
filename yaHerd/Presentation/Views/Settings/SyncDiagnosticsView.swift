//
//  SyncDiagnosticsView.swift
//  yaHerd
//

import Foundation
import SwiftUI

@MainActor
struct SyncDiagnosticsView: View {
    @Environment(\.collaborationDependencies) var collaborationDependencies
    var diagnosticsRepository: (any SyncDiagnosticsRepository)? { collaborationDependencies.diagnosticsRepository }
    var publicIDRepairService: (any PublicIDRepairService)? { collaborationDependencies.publicIDRepairService }
    var storageInfo: SyncDiagnosticsStorageInfo? { diagnosticsRepository?.storageInfo }
    @Environment(\.appDataAccessMode) var dataAccessMode
    @Environment(\.recoveryModeController) var recoveryModeController
    @EnvironmentObject var tagColorLibrary: TagColorLibraryStore
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
                LabeledContent(
                    "\(storageInfo?.technologyName ?? "Persistence") CloudKit",
                    value: persistenceCloudKitDescription
                )
                LabeledContent(
                    "CloudKit Container",
                    value: storageInfo?.cloudKitContainerIdentifier ?? "Unavailable"
                )
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
}
