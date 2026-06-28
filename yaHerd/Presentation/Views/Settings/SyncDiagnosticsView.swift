//
//  SyncDiagnosticsView.swift
//  yaHerd
//

import SwiftUI

struct SyncDiagnosticsView: View {
    @Environment(\.syncDiagnosticsRepository) private var diagnosticsRepository

    private let preferences: AppPreferencesProviding
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

    init(
        preferences: AppPreferencesProviding = AppPreferences(),
        checker: ICloudAvailabilityChecking = ICloudAvailabilityChecker(),
        schemaChecker: CloudKitSchemaChecking = CloudKitSchemaChecker()
    ) {
        self.preferences = preferences
        self.checker = checker
        self.schemaChecker = schemaChecker
    }

    var body: some View {
        List {
            Section("Launch State") {
                LabeledContent("Stored Preference", value: preferences.syncMode.displayName)
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
                .disabled(isRunningSchemaCheck)

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
                .disabled(isDeletingSyncData)

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

    private func deleteSyncData() {
        isDeletingSyncData = true
        resetResultMessage = nil

        Task {
            do {
                let resetService = SyncDataResetService(preferences: preferences)
                let summary = try await resetService.deleteICloudSyncData()

                await MainActor.run {
                    resetResultMessage = "Deleted \(summary.deletedCloudKitZoneCount.formatted()) CloudKit zones and \(summary.deletedCloudSettingsCount.formatted()) synced settings from iCloud. Local data was not deleted. Force quit and reopen yaHerd. Sync Mode is now Local Only."
                    isDeletingSyncData = false
                }

                await refreshDiagnostics()
            } catch {
                await MainActor.run {
                    resetResultMessage = "Delete failed: \(error.localizedDescription)"
                    isDeletingSyncData = false
                }
            }
        }
    }

    private func runSchemaCheck() {
        isRunningSchemaCheck = true
        schemaCheckResult = nil

        Task {
            let result = await schemaChecker.runCheck()
            await MainActor.run {
                schemaCheckResult = result
                isRunningSchemaCheck = false
            }
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
        if preferences.syncMode == .iCloud, launchSnapshot.actualStorageMode == .iCloud, launchSnapshot.cloudKitOpened {
            return "This install opened the SwiftData store with CloudKit mirroring enabled. If another install does not show the same state, that install is not participating in sync."
        }

        if launchSnapshot.actualStorageMode == .recovery {
            return "This install is running in recovery mode. Changes from this session are not being saved normally and will not sync."
        }

        if launchSnapshot.actualStorageMode == .unavailable {
            return "This install could not open persistent storage or an in-memory recovery store. Data was not loaded for that launch."
        }

        if preferences.syncMode == .iCloud, launchSnapshot.actualStorageMode != .iCloud {
            return "The stored preference says iCloud Sync, but this launch did not open CloudKit. Sync will not work from this install until the app opens in iCloud Sync mode."
        }

        return "This install is running Local Only. It will not sync until iCloud Sync is enabled and the app is restarted."
    }

    @MainActor
    private func refreshDiagnostics() async {
        launchSnapshot = AppLaunchDiagnostics.snapshot()
        loadCounts()

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
            countError = "Could not read local data counts: \(error.localizedDescription)"
        }
    }
}
