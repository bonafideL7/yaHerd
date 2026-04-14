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
    @State private var sessionPendingDelete: WorkingSession?
    @State private var showingDeleteAlert = false
    @State private var errorMessage: String?
    @State private var showingError = false

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
        .alert("Delete working session?", isPresented: $showingDeleteAlert, presenting: sessionPendingDelete) { selected in
            Button("Delete", role: .destructive) {
                deleteSession(selected)
            }
            Button("Cancel", role: .cancel) {}
        } message: { selected in
            if selected.status == .active {
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

    private func deleteSession(_ session: WorkingSession) {
        do {
            let repository = SwiftDataWorkingRepository(context: context)
            let useCase = DeleteWorkingSessionUseCase(repository: repository)
            try useCase.execute(session: session)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
