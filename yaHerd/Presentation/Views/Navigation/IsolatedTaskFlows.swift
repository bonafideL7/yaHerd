import SwiftUI

private struct FieldCheckPresentedFindingIdentityActionKey: EnvironmentKey {
    static let defaultValue: @MainActor (FieldCheckIdentityReference?) -> Void = { _ in }
}

private struct FieldCheckPresentedAnimalIDActionKey: EnvironmentKey {
    static let defaultValue: @MainActor (UUID?) -> Void = { _ in }
}

private struct WorkingPresentedQueueIdentityActionKey: EnvironmentKey {
    static let defaultValue: @MainActor (WorkingQueueIdentityReference?) -> Void = { _ in }
}

extension EnvironmentValues {
    var fieldCheckPresentedFindingIdentityDidChange: @MainActor (FieldCheckIdentityReference?) -> Void {
        get { self[FieldCheckPresentedFindingIdentityActionKey.self] }
        set { self[FieldCheckPresentedFindingIdentityActionKey.self] = newValue }
    }

    var fieldCheckPresentedAnimalIDDidChange: @MainActor (UUID?) -> Void {
        get { self[FieldCheckPresentedAnimalIDActionKey.self] }
        set { self[FieldCheckPresentedAnimalIDActionKey.self] = newValue }
    }

    var workingPresentedQueueIdentityDidChange: @MainActor (WorkingQueueIdentityReference?) -> Void {
        get { self[WorkingPresentedQueueIdentityActionKey.self] }
        set { self[WorkingPresentedQueueIdentityActionKey.self] = newValue }
    }
}

struct IsolatedFieldCheckAreaView: View {
    @Environment(AppNavigationState.self) private var navigation
    let onReturnHome: () -> Void

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        IsolatedFlowHomeButton(action: onReturnHome)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.workflowRouter.route {
        case .fieldCheckSession(let session):
            IdentityAwareFieldCheckSessionView(configuration: session)
        case .fieldCheckSessions(let mode):
            FieldChecksView(mode: mode, onSessionLaunch: { configuration in
                navigation.workflowRouter.route = .fieldCheckSession(configuration)
            })
        default:
            FieldChecksView(mode: .all, onSessionLaunch: { configuration in
                navigation.workflowRouter.route = .fieldCheckSession(configuration)
            })
        }
    }
}

struct IsolatedWorkAreaView: View {
    @Environment(AppNavigationState.self) private var navigation
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    @State private var stackResetToken = UUID()
    @State private var presentedQueueItemIdentity: WorkingQueueIdentityReference?

    let onReturnHome: () -> Void

    private var activeSessionID: UUID? {
        guard case .workingSession(let sessionID) = navigation.workflowRouter.route else {
            return nil
        }
        return sessionID
    }

    private var presentationID: WorkingFlowPresentationID {
        WorkingFlowPresentationID(
            sessionID: activeSessionID,
            resetToken: stackResetToken
        )
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        IsolatedFlowHomeButton(action: onReturnHome)
                    }
                }
        }
        .environment(\.workingPresentedQueueIdentityDidChange) { identity in
            presentedQueueItemIdentity = identity
        }
        .id(presentationID)
        .task(id: presentationID) {
            await observeIdentityMutations(for: activeSessionID)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.workflowRouter.route {
        case .workingSession(let sessionID):
            WorkingSessionDetailView(sessionID: sessionID)
        case .workingSessions:
            WorkingSessionsView { sessionID in
                navigation.workflowRouter.route = .workingSession(sessionID)
            }
        default:
            WorkingSessionsView { sessionID in
                navigation.workflowRouter.route = .workingSession(sessionID)
            }
        }
    }

    @MainActor
    private func observeIdentityMutations(for sessionID: UUID?) async {
        guard let sessionID else {
            presentedQueueItemIdentity = nil
            return
        }

        let mutationStream = workingDependencies.mutationStream
        let startingSequence = mutationStream.currentSequence

        for await event in mutationStream.events(after: startingSequence) {
            guard !Task.isCancelled else { return }
            guard activeSessionID == sessionID else { return }

            switch event.source {
            case .sharedStoreImport:
                guard let currentIdentity = loadWorkingIdentity(sessionID: sessionID) else {
                    continue
                }

                if currentIdentity.invalidates(presentedQueueItemIdentity) {
                    presentedQueueItemIdentity = nil
                    stackResetToken = UUID()
                    return
                }

            case .publicIDRepair:
                // Duplicate-ID repair can retain the same public ID on a different local object.
                // If a queue-item editor is open, rebuild the stack even when the IDs still compare
                // equal so it cannot remain bound to the discarded duplicate.
                guard presentedQueueItemIdentity != nil,
                      loadWorkingIdentity(sessionID: sessionID) != nil
                else {
                    continue
                }
                presentedQueueItemIdentity = nil
                stackResetToken = UUID()
                return

            case .local, .collaborationStateChange:
                break
            }
        }
    }

    @MainActor
    private func loadWorkingIdentity(sessionID: UUID) -> WorkingSessionIdentitySnapshot? {
        do {
            guard let detail = try workingDependencies.sessionDetailRepository.fetchSessionDetail(
                id: sessionID
            ) else {
                return nil
            }
            return WorkingSessionIdentitySnapshot(detail: detail)
        } catch {
            return nil
        }
    }
}

struct IdentityAwareFieldCheckSessionView: View {
    @Environment(\.fieldCheckFeatureDependencies) private var fieldCheckDependencies
    @State private var resetToken = UUID()
    @State private var presentedFindingIdentity: FieldCheckIdentityReference?
    @State private var presentedAnimalID: UUID?

    let configuration: FieldCheckSessionLaunchConfiguration

    private var presentationID: FieldCheckFlowPresentationID {
        FieldCheckFlowPresentationID(
            configurationID: configuration.id,
            resetToken: resetToken
        )
    }

    var body: some View {
        FieldCheckSessionDetailView(
            sessionID: configuration.sessionID,
            opensFindings: configuration.opensFindings,
            opensFlaggedRoster: configuration.opensFlaggedRoster,
            opensRemainingRoster: configuration.opensRemainingRoster,
            opensMissingRoster: configuration.opensMissingRoster,
            focusedFindingID: configuration.focusedFindingID
        )
        .environment(\.fieldCheckPresentedFindingIdentityDidChange) { identity in
            presentedFindingIdentity = identity
        }
        .environment(\.fieldCheckPresentedAnimalIDDidChange) { animalID in
            presentedAnimalID = animalID
        }
        .id(presentationID)
        .task(id: presentationID) {
            await observeIdentityMutations()
        }
    }

    @MainActor
    private func observeIdentityMutations() async {
        let mutationStream = fieldCheckDependencies.mutationStream
        let startingSequence = mutationStream.currentSequence

        for await event in mutationStream.events(after: startingSequence) {
            guard !Task.isCancelled else { return }

            switch event.source {
            case .sharedStoreImport:
                guard let currentIdentity = loadFieldCheckIdentity() else {
                    continue
                }

                if currentIdentity.invalidates(
                    presentedFinding: presentedFindingIdentity,
                    presentedAnimalID: presentedAnimalID
                ) {
                    presentedFindingIdentity = nil
                    presentedAnimalID = nil
                    resetToken = UUID()
                    return
                }

            case .publicIDRepair:
                // A duplicate-ID repair may preserve an ID while replacing the underlying local
                // object. Reset exceptional repair state even when the identity snapshot looks
                // unchanged; ordinary/no-op imports stay targeted to the currently presented IDs.
                guard loadFieldCheckIdentity() != nil else {
                    continue
                }
                presentedFindingIdentity = nil
                presentedAnimalID = nil
                resetToken = UUID()
                return

            case .local, .collaborationStateChange:
                break
            }
        }
    }

    @MainActor
    private func loadFieldCheckIdentity() -> FieldCheckSessionIdentitySnapshot? {
        do {
            guard let detail = try fieldCheckDependencies.sessionDetailRepository.fetchSessionDetail(
                id: configuration.sessionID
            ) else {
                return nil
            }
            return FieldCheckSessionIdentitySnapshot(detail: detail)
        } catch {
            return nil
        }
    }
}

private struct FieldCheckFlowPresentationID: Hashable {
    let configurationID: UUID
    let resetToken: UUID
}

private struct WorkingFlowPresentationID: Hashable {
    let sessionID: UUID?
    let resetToken: UUID
}

struct FieldCheckIdentityReference: Hashable {
    let id: UUID
    let relatedAnimalID: UUID?
}

struct FieldCheckSessionIdentitySnapshot: Equatable {
    let animalChecks: Set<FieldCheckIdentityReference>
    let findings: Set<FieldCheckIdentityReference>

    init(detail: FieldCheckSessionDetailSnapshot) {
        animalChecks = Set(detail.animalChecks.map {
            FieldCheckIdentityReference(id: $0.id, relatedAnimalID: $0.animalID)
        })
        findings = Set(detail.findings.map {
            FieldCheckIdentityReference(id: $0.id, relatedAnimalID: $0.animalID)
        })
    }

    func invalidates(
        presentedFinding: FieldCheckIdentityReference?,
        presentedAnimalID: UUID?
    ) -> Bool {
        if let presentedFinding, !findings.contains(presentedFinding) {
            return true
        }

        if let presentedAnimalID,
           !animalChecks.contains(where: { $0.relatedAnimalID == presentedAnimalID }) {
            return true
        }

        return false
    }
}

struct WorkingQueueIdentityReference: Hashable {
    let id: UUID
    let animalID: UUID?
    let destinationPastureID: UUID?

    init(item: WorkingQueueItemSnapshot) {
        id = item.id
        animalID = item.animalID
        destinationPastureID = item.destinationPastureID
    }
}

private struct WorkingSessionIdentitySnapshot: Equatable {
    let queueItems: Set<WorkingQueueIdentityReference>

    init(detail: WorkingSessionDetailSnapshot) {
        queueItems = Set(detail.queueItems.map(WorkingQueueIdentityReference.init(item:)))
    }

    func invalidates(_ presentedQueueItem: WorkingQueueIdentityReference?) -> Bool {
        guard let presentedQueueItem else { return false }
        return !queueItems.contains(presentedQueueItem)
    }
}

private struct IsolatedFlowHomeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Home", systemImage: "house")
        }
        .accessibilityLabel("Return Home")
    }
}
