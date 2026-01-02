//
//  WorkingSessionDetailView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct WorkingSessionDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: WorkingSession

    @State private var showingCollect = false
    @State private var showingFinish = false

    private var queuedCount: Int {
        session.queueItems.filter { $0.status == .queued || $0.status == .inProgress }.count
    }

    private var doneCount: Int {
        session.queueItems.filter { $0.status == .done }.count
    }

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Date", value: session.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Status", value: session.status.rawValue.capitalized)
                LabeledContent("Source Pasture", value: session.sourcePasture?.name ?? "—")
                LabeledContent("Protocol", value: session.protocolName)
                if !session.protocolItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Protocol Items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(session.protocolItems) { item in
                            Text("• \(item.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Queue") {
                HStack {
                    Text("Queued")
                    Spacer()
                    Text("\(queuedCount)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Done")
                    Spacer()
                    Text("\(doneCount)")
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    WorkingQueueView(session: session)
                } label: {
                    Label("Open Queue", systemImage: "list.bullet.rectangle")
                }

                NavigationLink {
                    WorkingSessionAnimalsView(session: session)
                } label: {
                    Label("Review / Edit Animals", systemImage: "pencil")
                }
            }
        }
        .navigationTitle("Working Session")
        .toolbar {
            if session.status == .active {
                ToolbarItem(placement: .primaryAction) {
                    Button("Collect") { showingCollect = true }
                        .disabled(session.sourcePasture == nil)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { showingFinish = true }
                        .disabled(session.queueItems.isEmpty)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    sessionPendingDelete = session
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete Session")
            }
        }
        .sheet(isPresented: $showingCollect) {
            WorkingCollectAnimalsView(session: session)
        }
        .sheet(isPresented: $showingFinish) {
            WorkingFinishSessionView(session: session)
        }
        .alert("Delete working session?", isPresented: $showingDeleteAlert, presenting: sessionPendingDelete) { s in
            Button("Delete", role: .destructive) {
                deleteSession(s)
            }
            Button("Cancel", role: .cancel) {}
        } message: { s in
            if s.status == .active {
                Text("Deleting an active session will return any animals currently in the working pen back to the source/collected pasture and remove the session records.")
            } else {
                Text("This will delete the session and its recorded work data.")
            }
        }
    }

    @State private var sessionPendingDelete: WorkingSession?
    @State private var showingDeleteAlert: Bool = false

    private func deleteSession(_ session: WorkingSession) {
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
        try? context.save()
    }
}
