import SwiftUI

extension SyncDiagnosticsView {
    func resolutionBinding(for issueID: String) -> Binding<String> {
        Binding(
            get: { publicIDResolutionSelections[issueID] ?? "" },
            set: { publicIDResolutionSelections[issueID] = $0 }
        )
    }

    func selectedCandidate(
        for issue: PublicIDRepairUnresolvedReference
    ) -> PublicIDRepairResolutionCandidate? {
        guard let selectedID = publicIDResolutionSelections[issue.id] else { return nil }
        return issue.candidates.first { $0.stableRecordIdentifier == selectedID }
    }

    func hasCompleteReferenceSelections(
        for assessment: PublicIDRepairAssessment
    ) -> Bool {
        assessment.unresolvedReferences.allSatisfy { issue in
            guard let selected = publicIDResolutionSelections[issue.id] else { return false }
            return issue.candidates.contains { $0.stableRecordIdentifier == selected }
        }
    }

    func scanPublicIDs() {
        guard let publicIDRepairService else {
            publicIDRepairError = "The public-ID repair service is not configured."
            return
        }

        isScanningPublicIDs = true
        publicIDRepairError = nil
        publicIDRepairReport = nil

        Task { @MainActor in
            do {
                let assessment = try await publicIDRepairService.scan()
                publicIDAssessment = assessment
                let validSelectionPairs: [(String, String)] = assessment.unresolvedReferences.compactMap { issue in
                    guard let selected = publicIDResolutionSelections[issue.id],
                          issue.candidates.contains(where: {
                              $0.stableRecordIdentifier == selected
                          })
                    else { return nil }
                    return (issue.id, selected)
                }
                publicIDResolutionSelections = Dictionary(
                    uniqueKeysWithValues: validSelectionPairs
                )
            } catch {
                publicIDRepairError = "Public-ID scan failed: \(UserVisibleErrorMessage.make(error))"
            }
            isScanningPublicIDs = false
        }
    }

    func repairPublicIDs() {
        guard let publicIDRepairService else {
            publicIDRepairError = "The public-ID repair service is not configured."
            return
        }

        isRepairingPublicIDs = true
        publicIDRepairError = nil
        publicIDRepairReport = nil
        let resolutions: [PublicIDRepairReferenceResolution] = (
            publicIDAssessment?.unresolvedReferences ?? []
        ).compactMap { issue in
            guard let selected = publicIDResolutionSelections[issue.id], !selected.isEmpty else {
                return nil
            }
            return PublicIDRepairReferenceResolution(
                unresolvedReferenceID: issue.id,
                selectedCandidateStableRecordIdentifier: selected
            )
        }

        Task { @MainActor in
            do {
                let report = try await publicIDRepairService.repair(
                    resolutions: resolutions
                )
                publicIDRepairReport = report
                publicIDAssessment = try await publicIDRepairService.scan()
                publicIDResolutionSelections = [:]
                loadCounts()
            } catch {
                publicIDRepairError = "Public-ID repair failed: \(UserVisibleErrorMessage.make(error))"
                publicIDAssessment = try? await publicIDRepairService.scan()
            }
            isRepairingPublicIDs = false
        }
    }

    func deleteSyncData() {
        isDeletingSyncData = true
        resetResultMessage = nil

        Task { @MainActor in
            do {
                guard let settingsSynchronizer = collaborationDependencies.settingsSynchronizer else {
                    throw SyncDiagnosticsSettingsError.settingsSynchronizerUnavailable
                }
                guard let writePolicy = collaborationDependencies.writePolicy else {
                    throw SyncDiagnosticsSettingsError.writePolicyUnavailable
                }
                let resetService = SyncDataResetService(
                    applicationSettings: applicationSettings,
                    settingsSynchronizer: settingsSynchronizer,
                    mutationGate: writePolicy.dataMutationGate
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

    func runSchemaCheck() {
        isRunningSchemaCheck = true
        schemaCheckResult = nil

        Task { @MainActor in
            let result = await schemaChecker.runCheck()
            schemaCheckResult = result
            isRunningSchemaCheck = false
        }
    }

    var swiftDataCloudKitDescription: String {
        launchSnapshot.actualStorageMode == .iCloud
            ? "Private: \(ModelContainerFactory.cloudKitContainerIdentifier)"
            : "Disabled"
    }

    var activeStoreDescription: String {
        switch launchSnapshot.actualStorageMode {
        case .recovery:
            ModelContainerFactory.recoveryStoreName
        case .unavailable:
            "None"
        case .localOnly, .iCloud:
            ModelContainerFactory.storeName
        }
    }

    var buildConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    var iCloudEnvironmentDescription: String {
        if let environment = Bundle.main.object(forInfoDictionaryKey: "com.apple.developer.icloud-container-environment") as? String {
            return environment
        }

        #if DEBUG
        return "Development (Debug build inferred)"
        #else
        return "Production (Release build inferred)"
        #endif
    }

    var explanation: String {
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
    func refreshDiagnostics() async {
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
    func loadCounts() {
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


enum SyncDiagnosticsSettingsError: LocalizedError {
    case settingsSynchronizerUnavailable
    case writePolicyUnavailable

    var errorDescription: String? {
        switch self {
        case .settingsSynchronizerUnavailable:
            "The application settings synchronizer is unavailable."
        case .writePolicyUnavailable:
            "The collaboration write policy is unavailable."
        }
    }
}
