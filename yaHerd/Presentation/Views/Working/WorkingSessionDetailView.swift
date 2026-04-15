//
//  WorkingSessionDetailView.swift
//  yaHerd
//

import SwiftUI

struct WorkingSessionDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var viewModel: WorkingSessionDetailViewModel

    @State private var showingCollect = false
    @State private var showingFinish = false
    @State private var showingDeleteAlert = false
    @State private var errorMessage: String?
    @State private var showingError = false

    init(sessionID: UUID) {
        _viewModel = StateObject(wrappedValue: WorkingSessionDetailViewModel(sessionID: sessionID, repository: EmptyWorkingRepository()))
    }

    var body: some View {
        Group {
            if let session = viewModel.session {
                List {
                    Section("Session") {
                        LabeledContent("Date", value: session.date.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Status", value: session.status.rawValue.capitalized)
                        LabeledContent("Source Pasture", value: session.sourcePastureName ?? "—")
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
                            Text("\(session.queuedCount)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Done")
                            Spacer()
                            Text("\(session.doneCount)")
                                .foregroundStyle(.secondary)
                        }

                        NavigationLink {
                            WorkingQueueView(sessionID: session.id)
                        } label: {
                            Label("Open Queue", systemImage: "list.bullet.rectangle")
                        }

                        NavigationLink {
                            WorkingSessionAnimalsView(sessionID: session.id)
                        } label: {
                            Label("Review / Edit Animals", systemImage: "pencil")
                        }
                    }
                }
                .toolbar {
                    if session.status == .active {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Collect") { showingCollect = true }
                                .disabled(session.sourcePastureID == nil)
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Finish") { showingFinish = true }
                                .disabled(session.queueItems.isEmpty)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete Session")
                    }
                }
                .sheet(isPresented: $showingCollect, onDismiss: reload) {
                    WorkingCollectAnimalsView(sessionID: session.id)
                }
                .sheet(isPresented: $showingFinish, onDismiss: reload) {
                    WorkingFinishSessionView(sessionID: session.id)
                }
                .alert("Delete working session?", isPresented: $showingDeleteAlert) {
                    Button("Delete", role: .destructive) {
                        deleteSession(sessionID: session.id)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if session.status == .active {
                        Text("Deleting an active session will return any animals currently in the working pen back to the source/collected pasture and remove the session records.")
                    } else {
                        Text("This will delete the session and its recorded work data.")
                    }
                }
            } else {
                ContentUnavailableView(
                    "Session not found",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("This working session may have been deleted.")
                )
            }
        }
        .navigationTitle("Working Session")
        .task {
            viewModel.configure(repository: dependencies.workingRepository)
            viewModel.load()
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

    private func reload() {
        viewModel.load()
    }

    private func deleteSession(sessionID: UUID) {
        do {
            let useCase = DeleteWorkingSessionUseCase(repository: dependencies.workingRepository)
            try useCase.execute(sessionID: sessionID)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
