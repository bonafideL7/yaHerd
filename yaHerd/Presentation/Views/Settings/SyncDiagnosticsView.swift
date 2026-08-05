//
//  SyncDiagnosticsView.swift
//  yaHerd
//

import SwiftUI

@MainActor
struct SyncDiagnosticsView: View {
    @Environment(\.collaborationDependencies) private var collaborationDependencies
    private var diagnosticsRepository: (any SyncDiagnosticsRepository)? { collaborationDependencies.diagnosticsRepository }
    private var publicIDRepairService: (any PublicIDRepairService)? { collaborationDependencies.publicIDRepairService }
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(\.recoveryModeController) private var recoveryModeController
    @Environment(ApplicationSettings.self) private var applicationSettings

    private let checker: ICloudAvailabilityChecking
    private let schemaChecker: CloudKitSchemaChecking

    @State private var launchSnapshot = AppLaunchDiagnostics.snapshot()
    @State private var iCloudStatusText = "Checking…"
    @State private var counts = SyncDiagnosticsCounts.empty
    @State private var countError: String?
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeletingSyncData = false
    @State private var resetResultMessage: String?
    @State private var isRunningSchemaCheck = false
    @State private var schemaCheckResult: CloudKitSchemaCheckResult?
    @State private var publicIDAssessment: PublicIDRepairAssessment?
    @State private var publicIDRepairReport: PublicIDRepairReport?
    @State private var publicIDRepairError: String?
    @State private var isScanningPublicIDs = false
    @State private var isRepairingPublicIDs = false
    @State private var isShowingPublicIDRepairConfirmation = false

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

                    if assessment.hasDuplicates {
                        Button {
                            isShowingPublicIDRepairConfirmation = true
                        } label: {
                            if isRepairingPublicIDs {
                                Label("Repairing Duplicate IDs…", systemImage: "hourglass")
                            } else {
                                Label("Back Up and Repair Duplicate IDs", systemImage: "wrench.and.screwdriver")
                            }
                        }
                        .disabled(
                            isRepairingPublicIDs
                                || isScanningPublicIDs
                                || dataAccessMode.isRecoveryMode
                        )

                        Text("Creates a JSON backup before changing any IDs, repairs related references, and validates the result before saving.")
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
            "Repair Duplicate Public IDs?",
            isPresented: $isShowingPublicIDRepairConfirmation,
            titleVisibility: .visible
        ) {
            Button("Back Up and Repair", role: .destructive) {
                repairPublicIDs()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("yaHerd will create a backup, assign deterministic replacement IDs, update related references, and validate the entire repair before saving. If validation fails, the changes are rolled back.")
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

    private func scanPublicIDs() {
        guard let publicIDRepairService else {
            publicIDRepairError = "The public-ID repair service is not configured."
            return
        }

        isScanningPublicIDs = true
        publicIDRepairError = nil
        publicIDRepairReport = nil

        Task { @MainActor in
            do {
                publicIDAssessment = try await publicIDRepairService.scan()
            } catch {
                publicIDRepairError = "Public-ID scan failed: \(UserVisibleErrorMessage.make(error))"
            }
            isScanningPublicIDs = false
        }
    }

    private func repairPublicIDs() {
        guard let publicIDRepairService else {
            publicIDRepairError = "The public-ID repair service is not configured."
            return
        }

        isRepairingPublicIDs = true
        publicIDRepairError = nil
        publicIDRepairReport = nil

        Task { @MainActor in
            do {
                let report = try await publicIDRepairService.repair()
                publicIDRepairReport = report
                publicIDAssessment = try await publicIDRepairService.scan()
                loadCounts()
            } catch {
                publicIDRepairError = "Public-ID repair failed: \(UserVisibleErrorMessage.make(error))"
            }
            isRepairingPublicIDs = false
        }
    }

    private func deleteSyncData() {
        isDeletingSyncData = true
        resetResultMessage = nil

        Task { @MainActor in
            do {
                guard let settingsSynchronizer = collaborationDependencies.settingsSynchronizer else {
                    throw SyncDiagnosticsSettingsError.settingsSynchronizerUnavailable
                }
                let resetService = SyncDataResetService(
                    applicationSettings: applicationSettings,
                    settingsSynchronizer: settingsSynchronizer
                )
                let summary = try await resetService.deleteICloudSyncData()

                resetResultMessage = "Deleted \(summary.deletedCloudKitZoneCount.formatted()) CloudKit zones and \(summary.deletedCloudSettingsCount.formatted()) synced settings from iCloud. Local data was not deleted. Force quit and reopen yaHerd. Sync Mode is now Local Only."
                isDeletingSyncData = false

                await refreshDiagnostics()
            } catch {
                resetResultMessage = "Delete failed: \(UserVisibleErrorMessage.make(error))"
                isDeletingSyncData = false
            }
        }
    }

    private func runSchemaCheck() {
        isRunningSchemaCheck = true
        schemaCheckResult = nil

        Task { @MainActor in
            let result = await schemaChecker.runCheck()
            schemaCheckResult = result
            isRunningSchemaCheck = false
        }
    }

    private var swiftDataCloudKitDescription: String {
        launchSnapshot.actualStorageMode == .iCloud
            ? "Private: \(ModelContainerFactory.cloudKitContainerIdentifier)"
            : "Disabled"
    }

    private var activeStoreDescription: String {
        switch launchSnapshot.actualStorageMode {
        case .recovery:
            ModelContainerFactory.recoveryStoreName
        case .unavailable:
            "None"
        case .localOnly, .iCloud:
            ModelContainerFactory.storeName
        }
    }

    private var buildConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    private var iCloudEnvironmentDescription: String {
        if let environment = Bundle.main.object(forInfoDictionaryKey: "com.apple.developer.icloud-container-environment") as? String {
            return environment
        }

        #if DEBUG
        return "Development (Debug build inferred)"
        #else
        return "Production (Release build inferred)"
        #endif
    }

    private var explanation: String {
        if applicationSettings.syncMode == .iCloud, launchSnapshot.actualStorageMode == .iCloud, launchSnapshot.cloudKitOpened {
            return "This install opened the SwiftData store with CloudKit mirroring enabled. If another install does not show the same state, that install is not participating in sync."
        }

        if launchSnapshot.actualStorageMode == .recovery {
            return "This install is running in recovery mode. Changes from this session are not being saved normally and will not sync."
        }

        if launchSnapshot.actualStorageMode == .unavailable {
            return "This install could not open persistent storage or an in-memory recovery store. Data was not loaded for that launch."
        }

        if applicationSettings.syncMode == .iCloud, launchSnapshot.actualStorageMode != .iCloud {
            return "The stored preference says iCloud Sync, but this launch did not open CloudKit. Sync will not work from this install until the app opens in iCloud Sync mode."
        }

        return "This install is running Local Only. It will not sync until iCloud Sync is enabled and the app is restarted."
    }

    @MainActor
    private func refreshDiagnostics() async {
        launchSnapshot = AppLaunchDiagnostics.snapshot()
        loadCounts()

        guard !dataAccessMode.isRecoveryMode else {
            iCloudStatusText = "Disabled in recovery mode"
            return
        }

        let status = await checker.checkAvailability()
        switch status {
        case .available:
            iCloudStatusText = "Available"
        case .unavailable(let reason):
            iCloudStatusText = reason.message
        }
    }

    @MainActor
    private func loadCounts() {
        guard let diagnosticsRepository else {
            counts = .empty
            countError = "Diagnostics repository is not configured."
            return
        }

        do {
            counts = try diagnosticsRepository.fetchCounts()
            countError = nil
        } catch {
            countError = "Could not read local data counts: \(UserVisibleErrorMessage.make(error))"
        }
    }
}

private enum SyncDiagnosticsSettingsError: LocalizedError {
    case settingsSynchronizerUnavailable

    var errorDescription: String? {
        "The application settings synchronizer is unavailable."
    }
}
