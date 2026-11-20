//
//  WorkingSessionsView.swift
//  yaHerd
//

import SwiftUI

/// The delete gesture owns its original Herd selection, not whatever Herd
/// happens to be active when SwiftUI eventually dispatches the confirmation.
@MainActor
struct PendingWorkingSessionDeletion {
    let session: WorkingSessionSummary
    let herdID: UUID
    let selectionRevision: UInt64

    func isCurrent(in selection: AppCurrentHerdSelection) -> Bool {
        selection.currentHerdID == herdID
            && selection.selectionRevision == selectionRevision
    }
}

struct WorkingSessionsView: View {
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    private var repository: any WorkingSessionsRepository { workingDependencies.sessionsRepository }
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(AppCurrentHerdSelection.self) private var herdSelection
    @StateObject private var viewModel: WorkingSessionsViewModel

    @State private var pendingDeletion: PendingWorkingSessionDeletion?
    @State private var showingDeleteAlert = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isDeletingSession = false

    private let onStartSessionSetup: () -> Void
    private let onSessionStarted: (UUID) -> Void

    init(
        onStartSessionSetup: @escaping () -> Void,
        onSessionStarted: @escaping (UUID) -> Void
    ) {
        self.onStartSessionSetup = onStartSessionSetup
        self.onSessionStarted = onSessionStarted
        _viewModel = StateObject(
            wrappedValue: WorkingSessionsViewModel(repository: EmptyWorkingRepository())
        )
    }

    private var activeSessions: [WorkingSessionSummary] {
        viewModel.sessions.filter { $0.status == .active }
    }

    private var finishedSessions: [WorkingSessionSummary] {
        viewModel.sessions.filter { $0.status != .active }
    }

    var body: some View {
        let displayedActiveSessions = activeSessions
        let displayedFinishedSessions = finishedSessions
        let originatingHerdID = herdSelection.currentHerdID
        let originatingSelectionRevision = herdSelection.selectionRevision

        return List {
            Section {
                NavigationLink {
                    TreatmentTemplatesView()
                } label: {
                    Label("Treatment Sets", systemImage: "syringe")
                }
                .disabled(isDeletingSession)
            }

            if displayedActiveSessions.isEmpty && displayedFinishedSessions.isEmpty {
                ContentUnavailableView(
                    "No working sessions",
                    systemImage: "wrench",
                    description: Text("Create a session to collect animals into the working pen.")
                )
            }

            if !displayedActiveSessions.isEmpty {
                Section("Active") {
                    ForEach(displayedActiveSessions) { session in
                        workingSessionNavigationRow(session)
                    }
                    .onDelete { offsets in
                        requestDelete(
                            from: displayedActiveSessions,
                            offsets: offsets,
                            originatingHerdID: originatingHerdID,
                            originatingSelectionRevision: originatingSelectionRevision
                        )
                    }
                    .deleteDisabled(dataAccessMode.isRecoveryMode || isDeletingSession)
                }
            }

            if !displayedFinishedSessions.isEmpty {
                Section("History") {
                    ForEach(displayedFinishedSessions) { session in
                        workingSessionNavigationRow(session)
                    }
                    .onDelete { offsets in
                        requestDelete(
                            from: displayedFinishedSessions,
                            offsets: offsets,
                            originatingHerdID: originatingHerdID,
                            originatingSelectionRevision: originatingSelectionRevision
                        )
                    }
                    .deleteDisabled(dataAccessMode.isRecoveryMode || isDeletingSession)
                }
            }
        }
        .navigationTitle("Working Sessions")
        .navigationBarBackButtonHidden(isDeletingSession)
        .interactiveDismissDisabled(isDeletingSession)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onStartSessionSetup) {
                    Image(systemName: "plus")
                }
                .disabled(!dataAccessMode.allowsDataMutations || isDeletingSession)
            }
        }
        .task {
            viewModel.configure(repository: repository)
            await viewModel.observe(mutationStream: workingDependencies.mutationStream)
        }
        .alert(
            "Delete working session?",
            isPresented: $showingDeleteAlert,
            presenting: pendingDeletion
        ) { pending in
            Button("Delete", role: .destructive) { deleteSession(pending) }
                .disabled(
                    !dataAccessMode.allowsDataMutations
                    || isDeletingSession
                    || !pending.isCurrent(in: herdSelection)
                )
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            if pending.session.status == .active {
                Text("Deleting an active session removes its records and releases animals still owned by it from the working pen. They return to their collected/source pasture when it still exists; otherwise they remain without a pasture assignment.")
            } else {
                Text("This will delete the session and its recorded work data.")
            }
        }
        .alert("Can’t Save", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if newValue != nil { showingError = true }
        }
        .onChange(of: herdSelection.selectionRevision) { _, _ in
            // A pending confirmation cannot cross Herd selection incarnations.
            pendingDeletion = nil
            showingDeleteAlert = false
        }
    }

    private func workingSessionNavigationRow(_ session: WorkingSessionSummary) -> some View {
        Button {
            onSessionStarted(session.id)
        } label: {
            WorkingSessionRow(session: session)
        }
        .disabled(isDeletingSession)
    }

    private func requestDelete(
        from list: [WorkingSessionSummary],
        offsets: IndexSet,
        originatingHerdID: UUID?,
        originatingSelectionRevision: UInt64
    ) {
        guard !isDeletingSession,
              let originatingHerdID,
              let index = offsets.first,
              index < list.count else {
            return
        }
        let request = PendingWorkingSessionDeletion(
            session: list[index],
            herdID: originatingHerdID,
            selectionRevision: originatingSelectionRevision
        )
        guard request.isCurrent(in: herdSelection) else { return }
        pendingDeletion = request
        showingDeleteAlert = true
    }

    private func deleteSession(_ pending: PendingWorkingSessionDeletion) {
        guard !isDeletingSession,
              dataAccessMode.allowsDataMutations,
              pending.isCurrent(in: herdSelection) else {
            pendingDeletion = nil
            return
        }
        isDeletingSession = true

        Task { @MainActor in
            defer { isDeletingSession = false }

            do {
                guard try await viewModel.deleteSession(
                    id: pending.session.id,
                    originatingHerdID: pending.herdID,
                    originatingSelectionRevision: pending.selectionRevision,
                    currentHerdSelection: herdSelection
                ) else { return }
                pendingDeletion = nil
                errorMessage = nil
            } catch {
                guard !Task.isCancelled,
                      pending.isCurrent(in: herdSelection) else { return }
                errorMessage = UserVisibleErrorMessage.make(error)
                showingError = true
            }
        }
    }
}

private struct WorkingSessionRow: View {
    let session: WorkingSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.sourcePastureName ?? "Working Session")
                    .font(.headline)
                Spacer()
                Text(session.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !session.treatmentTemplateName.isEmpty {
                    Text("• \(session.treatmentTemplateName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.totalQueueItems > 0 {
                    Text("\(session.completedQueueItems)/\(session.totalQueueItems)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

