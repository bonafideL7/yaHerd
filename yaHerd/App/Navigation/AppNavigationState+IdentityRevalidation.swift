import Foundation

@MainActor
protocol FocusedFieldCheckFindingValidating {
    func fieldCheckFindingExists(sessionID: UUID, findingID: UUID) throws -> Bool
}

extension RepositoryAppNavigationRestorationValidator: FocusedFieldCheckFindingValidating {
    func fieldCheckFindingExists(sessionID: UUID, findingID: UUID) throws -> Bool {
        guard let session = try fieldCheckRepository.fetchSessionDetail(id: sessionID) else {
            return false
        }
        return session.findings.contains { $0.id == findingID }
    }
}

private enum LiveWorkflowRevalidationPlan {
    case unchanged
    case replaceFieldCheckConfiguration(FieldCheckSessionLaunchConfiguration)
    case closeFieldCheck(openList: Bool)
    case closeWorkingSession(openList: Bool)
}

@MainActor
extension AppNavigationState {
    func revalidateIdentityBoundState(
        using validator: any AppNavigationRestorationValidating
    ) {
        do {
            let currentHerdID = try validator.currentHerdID()
            guard currentHerdID != nil else {
                selectedHerdID = nil
                clearIdentityBoundDestinations()
                return
            }

            // RootAppView persists immediately after live revalidation. Resolve every repository-
            // backed decision before mutating navigation so a later transient read failure cannot
            // leave a partially refreshed snapshot (for example, a new herd ID paired with stale
            // record routes from the previous coherent state).
            let validatedPath = try revalidatedPath(herdRouter.path, using: validator)
            let validatedSearchPath = try revalidatedPath(herdRouter.searchPath, using: validator)
            let shouldClearPastureFilter = try shouldClearIdentityBoundPastureFilter(
                using: validator
            )
            let workflowPlan = try liveWorkflowRevalidationPlan(using: validator)

            selectedHerdID = currentHerdID
            herdRouter.path = validatedPath
            herdRouter.searchPath = validatedSearchPath
            if shouldClearPastureFilter {
                herdRouter.filter.pasture = .any
            }
            apply(workflowPlan)
        } catch {
            // Live revalidation is best-effort. A transient repository read failure is not
            // evidence that the current herd or any presented identity disappeared. Preserve the
            // last coherent in-memory state and retry on a later mutation event.
            return
        }
    }

    private func revalidatedPath(
        _ path: [HerdRoute],
        using validator: any AppNavigationRestorationValidating
    ) throws -> [HerdRoute] {
        var validatedRoutes: [HerdRoute] = []

        for route in path {
            let isValid: Bool
            switch route {
            case .animal(let animalID):
                isValid = try validator.animalExists(id: animalID)
            case .pasture(let pastureID):
                isValid = try validator.pastureExists(id: pastureID)
            case .fieldChecks, .workingSessions:
                isValid = true
            }

            guard isValid else { break }
            validatedRoutes.append(route)
        }

        return validatedRoutes
    }

    private func shouldClearIdentityBoundPastureFilter(
        using validator: any AppNavigationRestorationValidating
    ) throws -> Bool {
        guard case .pasture(let pastureID) = herdRouter.filter.pasture else {
            return false
        }
        return try !validator.pastureExists(id: pastureID)
    }

    private func liveWorkflowRevalidationPlan(
        using validator: any AppNavigationRestorationValidating
    ) throws -> LiveWorkflowRevalidationPlan {
        switch workflowRouter.route {
        case .fieldCheckSession(let configuration):
            guard try validator.isActiveFieldCheckSession(id: configuration.sessionID) else {
                return .closeFieldCheck(openList: fullScreenWorkflow == .fieldCheck)
            }

            let validatedFocusedFindingID: UUID?
            if let findingID = configuration.focusedFindingID {
                let findingExists = try focusedFindingExists(
                    sessionID: configuration.sessionID,
                    findingID: findingID,
                    using: validator
                )
                validatedFocusedFindingID = findingExists ? findingID : nil
            } else {
                validatedFocusedFindingID = nil
            }

            // Keep the existing launch token when its identity-bound targets still resolve. The
            // isolated field-check flow observes mutation events and only tears down transient
            // editor state when an identity it already depended on is removed/rekeyed, or when a
            // public-ID repair occurs. Rebuilding every valid configuration here would dismiss
            // unsaved editors even for no-op or field-only shared imports.
            guard validatedFocusedFindingID != configuration.focusedFindingID else {
                return .unchanged
            }

            return .replaceFieldCheckConfiguration(
                FieldCheckSessionLaunchConfiguration(
                    sessionID: configuration.sessionID,
                    opensFindings: configuration.opensFindings,
                    opensFlaggedRoster: configuration.opensFlaggedRoster,
                    opensRemainingRoster: configuration.opensRemainingRoster,
                    opensMissingRoster: configuration.opensMissingRoster,
                    focusedFindingID: validatedFocusedFindingID
                )
            )

        case .workingSession(let sessionID):
            guard try validator.isActiveWorkingSession(id: sessionID) else {
                return .closeWorkingSession(openList: fullScreenWorkflow == .workingSession)
            }
            return .unchanged

        case .fieldCheckSessions, .workingSessions, .none:
            return .unchanged
        }
    }

    private func apply(_ plan: LiveWorkflowRevalidationPlan) {
        switch plan {
        case .unchanged:
            break

        case .replaceFieldCheckConfiguration(let configuration):
            workflowRouter.route = .fieldCheckSession(configuration)

        case .closeFieldCheck(let openList):
            closeFullScreenWorkflow()
            if openList {
                openFieldChecks()
            }

        case .closeWorkingSession(let openList):
            closeFullScreenWorkflow()
            if openList {
                openWorkingSessions()
            }
        }
    }

    /// A validator that cannot validate focused findings preserves the prior fail-closed behavior
    /// and reports the target as absent. A real repository read failure is propagated so the live
    /// revalidation transaction retains the complete prior navigation state.
    private func focusedFindingExists(
        sessionID: UUID,
        findingID: UUID,
        using validator: any AppNavigationRestorationValidating
    ) throws -> Bool {
        guard let findingValidator = validator as? any FocusedFieldCheckFindingValidating else {
            return false
        }
        return try findingValidator.fieldCheckFindingExists(
            sessionID: sessionID,
            findingID: findingID
        )
    }

    private func clearIdentityBoundDestinations() {
        herdRouter.path = stableListPrefix(herdRouter.path)
        herdRouter.searchPath = stableListPrefix(herdRouter.searchPath)

        if case .pasture = herdRouter.filter.pasture {
            herdRouter.filter.pasture = .any
        }

        switch workflowRouter.route {
        case .fieldCheckSession:
            let wasPresented = fullScreenWorkflow == .fieldCheck
            closeFullScreenWorkflow()
            if wasPresented {
                openFieldChecks()
            }

        case .workingSession:
            let wasPresented = fullScreenWorkflow == .workingSession
            closeFullScreenWorkflow()
            if wasPresented {
                openWorkingSessions()
            }

        case .fieldCheckSessions, .workingSessions, .none:
            break
        }
    }

    private func stableListPrefix(_ path: [HerdRoute]) -> [HerdRoute] {
        var stableRoutes: [HerdRoute] = []

        for route in path {
            switch route {
            case .fieldChecks, .workingSessions:
                stableRoutes.append(route)
            case .animal, .pasture:
                return stableRoutes
            }
        }

        return stableRoutes
    }
}
