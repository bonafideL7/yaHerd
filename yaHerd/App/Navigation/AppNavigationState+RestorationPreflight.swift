import Foundation

enum AppNavigationRestoreOutcome: Equatable {
    case applied
    case deferredValidation
}

@MainActor
extension AppNavigationState {
    /// Validates every repository-backed identity needed by a persisted snapshot before mutating
    /// navigation. A transient read failure leaves both the in-memory state and the stored payload
    /// untouched so a later retry can still restore the last coherent durable navigation state.
    @discardableResult
    func restorePreservingStoredSnapshot(
        from payload: String,
        using validator: any AppNavigationRestorationValidating
    ) -> AppNavigationRestoreOutcome {
        guard let snapshot = restorationSnapshotForPreflight(from: payload) else {
            // There is no valid durable snapshot to protect. Preserve the existing behavior for an
            // empty, corrupt, or unsupported payload so the app can establish the current herd ID.
            restore(from: payload, using: validator)
            return .applied
        }

        do {
            let preflightedValidator = try PreflightedAppNavigationRestorationValidator(
                snapshot: snapshot,
                base: validator
            )
            restore(from: payload, using: preflightedValidator)
            return .applied
        } catch {
            return .deferredValidation
        }
    }

    private func restorationSnapshotForPreflight(from payload: String) -> AppNavigationSnapshot? {
        guard !payload.isEmpty,
              let data = Data(base64Encoded: payload),
              let snapshot = try? JSONDecoder().decode(AppNavigationSnapshot.self, from: data),
              AppNavigationSnapshot.supportedVersions.contains(snapshot.version)
        else {
            return nil
        }
        return snapshot
    }
}

@MainActor
private struct PreflightedAppNavigationRestorationValidator: AppNavigationRestorationValidating {
    private let herdID: UUID?
    private let animalResults: [UUID: Bool]
    private let pastureResults: [UUID: Bool]
    private let fieldCheckSessionResults: [UUID: Bool]
    private let workingSessionResults: [UUID: Bool]

    init(
        snapshot: AppNavigationSnapshot,
        base: any AppNavigationRestorationValidating
    ) throws {
        let herdID = try base.currentHerdID()
        self.herdID = herdID

        let targetsCurrentHerd = snapshot.selectedHerdID == nil
            || snapshot.selectedHerdID == herdID
        guard targetsCurrentHerd else {
            animalResults = [:]
            pastureResults = [:]
            fieldCheckSessionResults = [:]
            workingSessionResults = [:]
            return
        }

        var animalIDs = Set<UUID>()
        var pastureIDs = Set<UUID>()
        for route in snapshot.herdRouter.path + (snapshot.herdRouter.searchPath ?? []) {
            switch route {
            case .animal(let animalID):
                animalIDs.insert(animalID)
            case .pasture(let pastureID):
                pastureIDs.insert(pastureID)
            case .fieldChecks, .workingSessions:
                break
            }
        }

        if case .pasture(let pastureID) = snapshot.herdRouter.filter.pasture {
            pastureIDs.insert(pastureID)
        }

        var fieldCheckSessionIDs = Set<UUID>()
        var workingSessionIDs = Set<UUID>()
        switch snapshot.activeWorkflow {
        case .fieldCheckSession(let sessionID):
            fieldCheckSessionIDs.insert(sessionID)
        case .workingSession(let sessionID):
            workingSessionIDs.insert(sessionID)
        case .none:
            break
        }

        animalResults = try Self.resolve(animalIDs) { id in
            try base.animalExists(id: id)
        }
        pastureResults = try Self.resolve(pastureIDs) { id in
            try base.pastureExists(id: id)
        }
        fieldCheckSessionResults = try Self.resolve(fieldCheckSessionIDs) { id in
            try base.isActiveFieldCheckSession(id: id)
        }
        workingSessionResults = try Self.resolve(workingSessionIDs) { id in
            try base.isActiveWorkingSession(id: id)
        }
    }

    func currentHerdID() throws -> UUID? {
        herdID
    }

    func animalExists(id: UUID) throws -> Bool {
        animalResults[id] ?? false
    }

    func pastureExists(id: UUID) throws -> Bool {
        pastureResults[id] ?? false
    }

    func isActiveFieldCheckSession(id: UUID) throws -> Bool {
        fieldCheckSessionResults[id] ?? false
    }

    func isActiveWorkingSession(id: UUID) throws -> Bool {
        workingSessionResults[id] ?? false
    }

    private static func resolve(
        _ ids: Set<UUID>,
        using read: (UUID) throws -> Bool
    ) throws -> [UUID: Bool] {
        var results: [UUID: Bool] = [:]
        results.reserveCapacity(ids.count)
        for id in ids {
            results[id] = try read(id)
        }
        return results
    }
}
