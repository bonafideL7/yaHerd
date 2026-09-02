import Foundation

@MainActor
private protocol FocusedFieldCheckFindingValidating {
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

@MainActor
extension AppNavigationState {
    func revalidateIdentityBoundState(
        using validator: any AppNavigationRestorationValidating
    ) {
        do {
            selectedHerdID = try validator.currentHerdID()
        } catch {
            selectedHerdID = nil
            clearIdentityBoundDestinations()
            return
        }

        guard selectedHerdID != nil else {
            clearIdentityBoundDestinations()
            return
        }

        herdRouter.path = revalidatedPath(herdRouter.path, using: validator)
        herdRouter.searchPath = revalidatedPath(herdRouter.searchPath, using: validator)

        if case .pasture(let pastureID) = herdRouter.filter.pasture,
           (try? validator.pastureExists(id: pastureID)) != true {
            herdRouter.filter.pasture = .any
        }

        revalidateActiveWorkflow(using: validator)
    }

    private func revalidatedPath(
        _ path: [HerdRoute],
        using validator: any AppNavigationRestorationValidating
    ) -> [HerdRoute] {
        var validatedRoutes: [HerdRoute] = []

        for route in path {
            let isValid: Bool
            switch route {
            case .animal(let animalID):
                isValid = (try? validator.animalExists(id: animalID)) == true
            case .pasture(let pastureID):
                isValid = (try? validator.pastureExists(id: pastureID)) == true
            case .fieldChecks, .workingSessions:
                isValid = true
            }

            guard isValid else { break }
            validatedRoutes.append(route)
        }

        return validatedRoutes
    }

    private func revalidateActiveWorkflow(
        using validator: any AppNavigationRestorationValidating
    ) {
        switch workflowRouter.route {
        case .fieldCheckSession(let configuration):
            guard (try? validator.isActiveFieldCheckSession(id: configuration.sessionID)) == true else {
                let wasPresented = fullScreenWorkflow == .fieldCheck
                closeFullScreenWorkflow()
                if wasPresented {
                    openFieldChecks()
                }
                return
            }

            let validatedFocusedFindingID = configuration.focusedFindingID.flatMap { findingID in
                focusedFindingExists(
                    sessionID: configuration.sessionID,
                    findingID: findingID,
                    using: validator
                ) ? findingID : nil
            }

            // Keep the existing launch token when its identity-bound targets still resolve. The
            // isolated field-check flow observes mutation events and only tears down transient
            // editor state when an identity it already depended on is removed/rekeyed, or when a
            // public-ID repair occurs. Rebuilding every valid configuration here would dismiss
            // unsaved editors even for no-op or field-only shared imports.
            if validatedFocusedFindingID != configuration.focusedFindingID {
                workflowRouter.route = .fieldCheckSession(
                    FieldCheckSessionLaunchConfiguration(
                        sessionID: configuration.sessionID,
                        opensFindings: configuration.opensFindings,
                        opensFlaggedRoster: configuration.opensFlaggedRoster,
                        opensRemainingRoster: configuration.opensRemainingRoster,
                        opensMissingRoster: configuration.opensMissingRoster,
                        focusedFindingID: validatedFocusedFindingID
                    )
                )
            }

        case .workingSession(let sessionID):
            guard (try? validator.isActiveWorkingSession(id: sessionID)) == true else {
                let wasPresented = fullScreenWorkflow == .workingSession
                closeFullScreenWorkflow()
                if wasPresented {
                    openWorkingSessions()
                }
                return
            }

        case .fieldCheckSessions, .workingSessions, .none:
            break
        }
    }

    private func focusedFindingExists(
        sessionID: UUID,
        findingID: UUID,
        using validator: any AppNavigationRestorationValidating
    ) -> Bool {
        guard let findingValidator = validator as? any FocusedFieldCheckFindingValidating else {
            return false
        }
        return (try? findingValidator.fieldCheckFindingExists(
            sessionID: sessionID,
            findingID: findingID
        )) == true
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
