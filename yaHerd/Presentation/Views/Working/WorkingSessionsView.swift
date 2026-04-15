//
//  WorkingSessionsView.swift
//  yaHerd
//

import SwiftUI

struct WorkingSessionsView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var viewModel: WorkingSessionsViewModel

    @State private var showingNewSession = false
    @State private var sessionPendingDeleteID: UUID?
    @State private var showingDeleteAlert: Bool = false
    @State private var errorMessage: String?
    @State private var showingError = false

    init() {
        _viewModel = StateObject(wrappedValue: WorkingSessionsViewModel(repository: EmptyWorkingRepository()))
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
                        NavigationLink {
                            WorkingSessionDetailView(sessionID: session.id)
                        } label: {
                            WorkingSessionRow(session: session)
                        }
                    }
                    .onDelete { offsets in
                        requestDelete(from: activeSessions, offsets: offsets)
                    }
                }
            }

            if !finishedSessions.isEmpty {
                Section("History") {
                    ForEach(finishedSessions) { session in
                        NavigationLink {
                            WorkingSessionDetailView(sessionID: session.id)
                        } label: {
                            WorkingSessionRow(session: session)
                        }
                    }
                    .onDelete { offsets in
                        requestDelete(from: finishedSessions, offsets: offsets)
                    }
                }
            }
        }
        .navigationTitle("Work")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewSession = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ProtocolTemplatesView()
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Protocols")
            }
        }
        .task {
            viewModel.configure(repository: dependencies.workingRepository)
            viewModel.load()
        }
        .onChange(of: showingNewSession) { _, isPresented in
            if !isPresented {
                viewModel.load()
            }
        }
        .sheet(isPresented: $showingNewSession) {
            NewWorkingSessionView()
        }
        .alert("Delete working session?", isPresented: $showingDeleteAlert, presenting: pendingSession) { session in
            Button("Delete", role: .destructive) { deleteSession(session) }
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

    private var pendingSession: WorkingSessionSummary? {
        guard let sessionPendingDeleteID else { return nil }
        return viewModel.sessions.first(where: { $0.id == sessionPendingDeleteID })
    }

    private func requestDelete(from list: [WorkingSessionSummary], offsets: IndexSet) {
        guard let idx = offsets.first, idx < list.count else { return }
        sessionPendingDeleteID = list[idx].id
        showingDeleteAlert = true
    }

    private func deleteSession(_ session: WorkingSessionSummary) {
        do {
            let useCase = DeleteWorkingSessionUseCase(repository: dependencies.workingRepository)
            try useCase.execute(sessionID: session.id)
            viewModel.load()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

private struct WorkingSessionRow: View {
    let session: WorkingSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.protocolName)
                    .font(.headline)
                Spacer()
                Text(session.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let source = session.sourcePastureName {
                    Text("• \(source)")
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

