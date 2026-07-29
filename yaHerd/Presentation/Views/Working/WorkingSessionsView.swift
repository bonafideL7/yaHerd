//
//  WorkingSessionsView.swift
//  yaHerd
//

import SwiftUI

struct WorkingSessionsView: View {
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    private var repository: any WorkingSessionsRepository { workingDependencies.sessionsRepository }
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @StateObject private var viewModel: WorkingSessionsViewModel

    @State private var showingNewSession = false
    @State private var sessionPendingDeleteID: UUID?
    @State private var showingDeleteAlert = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var startedRoute: StartedWorkingSessionRoute?

    private let onSessionStarted: ((UUID) -> Void)?

    init(onSessionStarted: ((UUID) -> Void)? = nil) {
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
        List {
            if activeSessions.isEmpty && finishedSessions.isEmpty {
                ContentUnavailableView(
                    "No working sessions",
                    systemImage: "wrench",
                    description: Text("Create a session to collect animals into the working pen.")
                )
            }

            if !activeSessions.isEmpty {
                Section("Active") {
                    ForEach(activeSessions) { session in
                        workingSessionNavigationRow(session)
                    }
                    .onDelete { offsets in
                        requestDelete(from: activeSessions, offsets: offsets)
                    }
                    .deleteDisabled(dataAccessMode.isRecoveryMode)
                }
            }

            if !finishedSessions.isEmpty {
                Section("History") {
                    ForEach(finishedSessions) { session in
                        workingSessionNavigationRow(session)
                    }
                    .onDelete { offsets in
                        requestDelete(from: finishedSessions, offsets: offsets)
                    }
                    .deleteDisabled(dataAccessMode.isRecoveryMode)
                }
            }
        }
        .navigationTitle("Working Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewSession = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!dataAccessMode.allowsDataMutations)
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TreatmentTemplatesView()
                } label: {
                    Image(systemName: "syringe")
                }
                .accessibilityLabel("Vaccinations")
            }
        }
        .task {
            viewModel.configure(repository: repository)
            viewModel.load()
        }
        .onChange(of: showingNewSession) { _, isPresented in
            if !isPresented {
                viewModel.load()
            }
        }
        .navigationDestination(isPresented: $showingNewSession) {
            NewWorkingSessionView(
                wrapsInNavigationStack: false,
                onSessionCreated: handleSessionStarted
            )
        }
        .navigationDestination(item: $startedRoute) { route in
            WorkingSessionDetailView(sessionID: route.id)
        }
        .alert(
            "Delete working session?",
            isPresented: $showingDeleteAlert,
            presenting: pendingSession
        ) { session in
            Button("Delete", role: .destructive) { deleteSession(session) }
                .disabledWhenDataReadOnly()
            Button("Cancel", role: .cancel) {}
        } message: { session in
            if session.status == .active {
                Text("Deleting an active session will return any animals currently in the working pen back to the source/collected pasture and remove the session records.")
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
    }

    @ViewBuilder
    private func workingSessionNavigationRow(_ session: WorkingSessionSummary) -> some View {
        if let onSessionStarted {
            Button {
                onSessionStarted(session.id)
            } label: {
                WorkingSessionRow(session: session)
            }
        } else {
            NavigationLink {
                WorkingSessionDetailView(sessionID: session.id)
            } label: {
                WorkingSessionRow(session: session)
            }
        }
    }

    private func handleSessionStarted(_ sessionID: UUID) {
        showingNewSession = false
        if let onSessionStarted {
            onSessionStarted(sessionID)
        } else {
            startedRoute = StartedWorkingSessionRoute(id: sessionID)
        }
    }

    private var pendingSession: WorkingSessionSummary? {
        guard let sessionPendingDeleteID else { return nil }
        return viewModel.sessions.first(where: { $0.id == sessionPendingDeleteID })
    }

    private func requestDelete(from list: [WorkingSessionSummary], offsets: IndexSet) {
        guard let index = offsets.first, index < list.count else { return }
        sessionPendingDeleteID = list[index].id
        showingDeleteAlert = true
    }

    private func deleteSession(_ session: WorkingSessionSummary) {
        do {
            try repository.deleteSession(id: session.id)
            viewModel.load()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
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

private struct StartedWorkingSessionRoute: Identifiable, Hashable {
    let id: UUID
}
