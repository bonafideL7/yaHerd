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
        }
        .sheet(isPresented: $showingCollect) {
            WorkingCollectAnimalsView(session: session)
        }
        .sheet(isPresented: $showingFinish) {
            WorkingFinishSessionView(session: session)
        }
    }
}
