//
//  WorkingSessionsView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct WorkingSessionsView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \WorkingSession.date, order: .reverse)
    private var sessions: [WorkingSession]

    @State private var showingNewSession = false
    @State private var sessionPendingDelete: WorkingSession?
    @State private var showingDeleteAlert: Bool = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var activeSessions: [WorkingSession] {
        sessions.filter { $0.status == .active }
    }

    private var finishedSessions: [WorkingSession] {
        sessions.filter { $0.status != .active }
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
                            WorkingSessionDetailView(session: session)
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
                            WorkingSessionDetailView(session: session)
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
        .sheet(isPresented: $showingNewSession) {
            NewWorkingSessionView()
        }
        .alert("Delete working session?", isPresented: $showingDeleteAlert, presenting: sessionPendingDelete) { s in
            Button("Delete", role: .destructive) { deleteSession(s) }
            Button("Cancel", role: .cancel) {}
        } message: { s in
            if s.status == .active {
                Text("Deleting an active session will return any animals currently in the working pen back to the source/collected pasture and remove the session records.")
            } else {
                Text("This will delete the session and its recorded work data.")
            }
        }
        .alert("Can’t Save", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func requestDelete(from list: [WorkingSession], offsets: IndexSet) {
        // Only handle the first one for now (swipe-to-delete is typically single-row).
        guard let idx = offsets.first, idx < list.count else { return }
        sessionPendingDelete = list[idx]
        showingDeleteAlert = true
    }

    private func deleteSession(_ session: WorkingSession) {
        do {
        // Return any animals still in the working pen for this session.
        for item in session.queueItems {
            guard let animal = item.animal else { continue }
            if animal.activeWorkingSession?.persistentModelID == session.persistentModelID || animal.location == .workingPen {
                let dest = item.collectedFromPasture ?? session.sourcePasture
                animal.pasture = dest
                animal.location = .pasture
                animal.activeWorkingSession = nil
            }
        }

        // Delete session-linked records (treatments, preg checks, session-tied health records).
        // NOTE: SwiftData predicate macros are unreliable when comparing relationship values in predicates.
        // Fetch and filter in-memory instead.
        let sid = session.persistentModelID

        if let all = try? context.fetch(FetchDescriptor<WorkingTreatmentRecord>()) {
            for r in all where r.session?.persistentModelID == sid { context.delete(r) }
        }
        if let all = try? context.fetch(FetchDescriptor<PregnancyCheck>()) {
            for c in all where c.workingSession?.persistentModelID == sid { context.delete(c) }
        }
        if let all = try? context.fetch(FetchDescriptor<HealthRecord>()) {
            for h in all where h.workingSession?.persistentModelID == sid { context.delete(h) }
        }

        context.delete(session)
        try context.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

private struct WorkingSessionRow: View {
    let session: WorkingSession

    private var total: Int { session.queueItems.count }
    private var done: Int { session.queueItems.filter { $0.status == .done }.count }

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
                if let source = session.sourcePasture?.name {
                    Text("• \(source)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if total > 0 {
                    Text("\(done)/\(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
