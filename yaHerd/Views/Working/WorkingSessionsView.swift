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
                        NavigationLink(value: session) {
                            WorkingSessionRow(session: session)
                        }
                    }
                }
            }

            if !finishedSessions.isEmpty {
                Section("History") {
                    ForEach(finishedSessions) { session in
                        NavigationLink(value: session) {
                            WorkingSessionRow(session: session)
                        }
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
        .navigationDestination(for: WorkingSession.self) { session in
            WorkingSessionDetailView(session: session)
        }
        .sheet(isPresented: $showingNewSession) {
            NewWorkingSessionView()
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
