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

    func requiresBridgeCanonicalIssueRefresh(
        _ issue: PublicIDRepairUnresolvedReference
    ) -> Bool {
        guard issue.kind == .canonicalRecord,
              issue.entityType != .herd,
              issue.stableRecordIdentifier.hasPrefix("bridge-canonical|") else {
            return false
        }
        return !issue.candidates.contains {
            $0.stableRecordIdentifier.hasPrefix("bridge-canonical-restore|")
        }
            || !issue.candidates.contains {
                $0.stableRecordIdentifier.hasPrefix("bridge-canonical-remove|")
            }
    }

    func hasCompleteReferenceSelections(
        for assessment: PublicIDRepairAssessment
    ) -> Bool {
        assessment.unresolvedReferences.allSatisfy { issue in
            // Older pending convergence journals can contain canonical bridge blockers that
            // predate the explicit restore/remove recovery choices. Allow exactly that stale
            // blocker to run once without a user selection so convergence can re-observe the
            // bridge and persist the current deliberate choices. The regenerated blocker again
            // requires an explicit selection before any bridge mutation continues.
            if requiresBridgeCanonicalIssueRefresh(issue) {
                return true
            }

            guard let selected = publicIDResolutionSelections[issue.id] else { return false }
            return issue.candidates.contains { $0.stableRecordIdentifier == selected }
        }
    }

    var selectedPreparedHerdRetirement: PublicIDRepairUnresolvedReference? {
        (publicIDAssessment?.unresolvedReferences ?? []).first { issue in
            guard issue.kind == .preparedHerdRecovery,
                  let selectedID = publicIDResolutionSelections[issue.id] else {
                return false
            }
            return selectedID.hasPrefix("retire-prepared-herd|")
        }
    }

    var selectedSharedRecordRestoration: PublicIDRepairUnresolvedReference? {
        (publicIDAssessment?.unresolvedReferences ?? []).first { issue in
            guard issue.kind == .canonicalRecord,
                  issue.entityType != .herd,
                  let selectedID = publicIDResolutionSelections[issue.id] else {
                return false
            }
            return selectedID.hasPrefix("bridge-canonical-restore|")
        }
    }

    var selectedStaleSharedRecordRemoval: PublicIDRepairUnresolvedReference? {
        (publicIDAssessment?.unresolvedReferences ?? []).first { issue in
            guard issue.kind == .canonicalRecord,
                  issue.entityType != .herd,
                  let selectedID = publicIDResolutionSelections[issue.id] else {
                return false
            }
            return selectedID.hasPrefix("bridge-canonical-remove|")
        }
    }

    var publicIDRepairConfirmationTitle: String {
        if selectedSharedRecordRestoration != nil {
            return "Restore Shared Record?"
        }
        if selectedStaleSharedRecordRemoval != nil {
            return "Remove Stale Shared Record?"
        }
        if selectedPreparedHerdRetirement != nil {
            return "Permanently Retire Prepared Shared Herd?"
        }
        if publicIDAssessment?.requiresBridgeConvergence == true,
           publicIDAssessment?.hasDuplicates == false {
            return "Finish Shared-Data Convergence?"
        }
        return "Repair Duplicate Public IDs?"
    }

    var publicIDRepairConfirmationButtonTitle: String {
        if selectedSharedRecordRestoration != nil {
            return "Restore Record"
        }
        if selectedStaleSharedRecordRemoval != nil {
            return "Remove Stale Shared Record"
        }
        if selectedPreparedHerdRetirement != nil {
            return "Retire Exact Shared Herd"
        }
        if publicIDAssessment?.requiresBridgeConvergence == true,
           publicIDAssessment?.hasDuplicates == false {
            return "Finish Convergence"
        }
        return "Back Up and Repair"
    }

    var publicIDRepairConfirmationRole: ButtonRole? {
        if selectedStaleSharedRecordRemoval != nil || selectedPreparedHerdRetirement != nil {
            return .destructive
        }
        return nil
    }

    var publicIDRepairConfirmationMessage: String {
        if let restoredRecord = selectedSharedRecordRestoration {
            let summary = publicIDIssueSummary(restoredRecord)
            return "The verified shared bridge contains \(summary), but that record is missing from local data. yaHerd will restore that exact shared record into local data with a new unique public ID, then continue shared-data convergence. Existing local records are not replaced or deleted."
        }
        if let staleRecord = selectedStaleSharedRecordRemoval {
            let summary = publicIDIssueSummary(staleRecord)
            return "The shared bridge contains \(summary), but none of the repaired local records represents that event or object. This removes only that stale shared bridge record during convergence; it does not delete local data. yaHerd will then export the repaired local graph and verify reconciliation before clearing the repair gate."
        }
        if let retirement = selectedPreparedHerdRetirement {
            return "You chose intentional deletion for Herd \(retirement.referencedPublicID.uuidString). yaHerd will first persist that decision in the existing repair manifest, then verify the exact journaled bridge location, fingerprint, and write authority before deleting only that Herd's prepared shared graph and tombstones. It will verify the target is retired before removing the convergence obligation. This cannot be inferred or performed automatically."
        }
        return "yaHerd will hold the mutation gate, verify the bound shared-data target, create a backup for every local mutation generation, durably journal the repair before local changes, apply only manifest-authorized identity decisions, then converge only affected writable bridges. Edits stay blocked until reconciliation and the final global uniqueness scan pass."
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
                rebuildPublicIDDisplayCache(for: assessment)
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
                clearPublicIDDisplayCache()
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
        let issues = publicIDAssessment?.unresolvedReferences ?? []
        let resolutions: [PublicIDRepairReferenceResolution] = issues.compactMap { issue in
            guard let selected = publicIDResolutionSelections[issue.id], !selected.isEmpty else {
                return nil
            }
            return PublicIDRepairReferenceResolution(
                unresolvedReferenceID: issue.id,
                selectedCandidateStableRecordIdentifier: selected
            )
        }
        let indeterminateRecoveryChoice: PublicIDRepairRecoveryChoice? = issues
            .first(where: { $0.kind == .indeterminateLocalRepairRecovery })
            .flatMap { issue in
                publicIDResolutionSelections[issue.id].flatMap(PublicIDRepairRecoveryChoice.init(rawValue:))
            }

        Task { @MainActor in
            do {
                // A single canonical bridge blocker created by an older build can lack the current
                // explicit restore/remove choices. Remove only that stale persisted blocker and let
                // convergence re-observe the same bridge record. It immediately stops again with
                // current deliberate choices; no import/export proceeds until the regenerated issue
                // is explicitly resolved.
                if issues.count == 1,
                   let issue = issues.first,
                   requiresBridgeCanonicalIssueRefresh(issue) {
                    guard let writePolicy = collaborationDependencies.writePolicy else {
                        throw SyncDiagnosticsSettingsError.writePolicyUnavailable
                    }
                    try writePolicy.dataMutationGate.recordBridgeResolutionIssues([])
                }

                let report: PublicIDRepairReport
                if let indeterminateRecoveryChoice {
                    report = try await publicIDRepairService.recoverIndeterminateRepair(
                        action: indeterminateRecoveryChoice
                    )
                } else {
                    report = try await publicIDRepairService.repair(
                        resolutions: resolutions
                    )
                }
                publicIDRepairReport = report
                let assessment = try await publicIDRepairService.scan()
                rebuildPublicIDDisplayCache(for: assessment)
                publicIDAssessment = assessment
                publicIDResolutionSelections = [:]
                loadCounts()
            } catch {
                publicIDRepairError = "Public-ID repair failed: \(UserVisibleErrorMessage.make(error))"
                if let assessment = try? await publicIDRepairService.scan() {
                    rebuildPublicIDDisplayCache(for: assessment)
                    publicIDAssessment = assessment
                } else {
                    clearPublicIDDisplayCache()
                    publicIDAssessment = nil
                }
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
