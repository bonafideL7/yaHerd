//
//  SyncDiagnosticsView.swift
//  yaHerd
//

import SwiftUI

@MainActor
struct SyncDiagnosticsView: View {
    @Environment(\.collaborationDependencies) var collaborationDependencies
    var diagnosticsRepository: (any SyncDiagnosticsRepository)? { collaborationDependencies.diagnosticsRepository }
    var publicIDRepairService: (any PublicIDRepairService)? { collaborationDependencies.publicIDRepairService }
    @Environment(\.appDataAccessMode) var dataAccessMode
    @Environment(\.recoveryModeController) var recoveryModeController
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
                        Label("Shared-data convergence must be completed", systemImage: "arrow.triangle.2.circlepath.icloud")
                            .foregroundStyle(.orange)
                        Text("SwiftData was repaired previously, but export verification did not complete. Normal changes and synchronization remain blocked until this action succeeds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if assessment.hasBlockingIssues {
                        Label("Choose the intended record for every reference", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)

                        ForEach(assessment.unresolvedReferences) { issue in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(issue.recordDescription) — \(issue.fieldName)")
                                    .font(.subheadline.weight(.semibold))
                                Text(issue.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)

                                Picker(
                                    "Intended record",
                                    selection: resolutionBinding(for: issue.id)
                                ) {
                                    Text("Choose a record").tag("")
                                    ForEach(issue.candidates) { candidate in
                                        Text(candidate.recordDescription)
                                            .tag(candidate.stableRecordIdentifier)
                                    }
                                }
                                .pickerStyle(.menu)
                                .accessibilityLabel("Intended record for \(issue.recordDescription) \(issue.fieldName)")

                                if let selectedCandidate = selectedCandidate(for: issue) {
                                    Text(selectedCandidate.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("Resulting public ID: \(selectedCandidate.resultingPublicID.uuidString)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if assessment.hasRepairWork {
                        Button {
                            isShowingPublicIDRepairConfirmation = true
                        } label: {
                            if isRepairingPublicIDs {
                                Label("Repairing Duplicate IDs…", systemImage: "hourglass")
                            } else if assessment.requiresBridgeConvergence && !assessment.hasDuplicates {
                                Label("Finish Shared-Data Convergence", systemImage: "arrow.triangle.2.circlepath.icloud")
                            } else {
                                Label("Back Up and Repair Duplicate IDs", systemImage: "wrench.and.screwdriver")
                            }
                        }
                        .disabled(
                            isRepairingPublicIDs
                                || isScanningPublicIDs
                                || dataAccessMode.isRecoveryMode
                                || !hasCompleteReferenceSelections(for: assessment)
                        )

                        Text("Creates a JSON backup before changing IDs, applies your reference choices in the same repair transaction, exports repaired IDs without importing stale bridge data, and validates both stores before unblocking edits.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        }
        .confirmationDialog(
            publicIDAssessment?.requiresBridgeConvergence == true
                && publicIDAssessment?.hasDuplicates == false
                ? "Finish Shared-Data Convergence?"
                : "Repair Duplicate Public IDs?",
            isPresented: $isShowingPublicIDRepairConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                publicIDAssessment?.requiresBridgeConvergence == true
                    && publicIDAssessment?.hasDuplicates == false
                    ? "Finish Convergence"
                    : "Back Up and Repair",
                role: .destructive
            ) {
                repairPublicIDs()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("yaHerd will hold the mutation gate, import current shared data before repair, create a backup, apply deliberate choices, assign deterministic replacement IDs, export the repaired graph without re-importing stale bridge records, and validate reconciliation before allowing edits again.")
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
