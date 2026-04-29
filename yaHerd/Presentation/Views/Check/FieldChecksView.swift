import SwiftUI

struct FieldChecksView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var model = FieldChecksViewModel()
    @State private var showingStartPastureCheck = false

    private var repository: any FieldCheckRepository {
        dependencies.fieldCheckRepository
    }

    private var isEmpty: Bool {
        model.activeSessions.isEmpty
        && model.openFindings.isEmpty
        && model.recentSessions.isEmpty
    }

    var body: some View {
        Group {
            if isEmpty {
                FieldChecksEmptyState {
                    showingStartPastureCheck = true
                }
            } else {
                List {
                    if !model.activeSessions.isEmpty {
                        Section("In Progress") {
                            ForEach(model.activeSessions) { session in
                                NavigationLink {
                                    FieldCheckSessionDetailView(sessionID: session.id)
                                } label: {
                                    FieldCheckSessionSummaryRow(session: session)
                                }
                            }
                        }
                    }

                    if !model.openFindings.isEmpty {
                        Section("Open Findings") {
                            ForEach(model.openFindings) { finding in
                                NavigationLink {
                                    openFindingDestination(for: finding)
                                } label: {
                                    FieldCheckFindingRow(finding: finding)
                                }
                            }
                        }
                    }

                    if !model.recentSessions.isEmpty {
                        Section("Recent Checks") {
                            ForEach(model.recentSessions) { session in
                                NavigationLink {
                                    FieldCheckSessionDetailView(sessionID: session.id)
                                } label: {
                                    FieldCheckSessionSummaryRow(session: session)
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    model.load(using: repository)
                }
            }
        }
        .navigationTitle("Pasture Checks")
        .navigationDestination(isPresented: $showingStartPastureCheck) {
            FieldCheckSessionDetailView()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingStartPastureCheck = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Start Pasture Check")
            }
        }
        .task {
            model.load(using: repository)
        }
        .alert("Can't Load Checks", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func openFindingDestination(for finding: FieldCheckFindingSnapshot) -> some View {
        FieldCheckSessionDetailView(sessionID: finding.sessionID, opensFindings: true)
    }


    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
                }
            }
        )
    }


}

private struct FieldChecksEmptyState: View {
    let onStartPastureCheck: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checklist")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No pasture checks")
                    .font(.title3.weight(.semibold))

                Text("Start a pasture check to verify head counts, record findings, and capture notes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onStartPastureCheck) {
                Label("Start Pasture Check", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(.systemGroupedBackground))
    }
}

private struct FieldCheckSessionSummaryRow: View {
    let session: FieldCheckSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .fontWeight(.semibold)
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                FieldCheckBadge(
                    title: session.isCompleted ? "Done" : "Open",
                    tint: session.isCompleted ? Color.green : Color.orange
                )
            }

            HStack(spacing: 10) {
                if let pastureName = session.pastureName {
                    Label(pastureName, systemImage: "leaf")
                }

                Label("\(session.totalSeen)/\(session.expectedHeadCountSnapshot)", systemImage: "number.circle")

                if session.openFindingsCount > 0 {
                    Label("\(session.openFindingsCount)", systemImage: "exclamationmark.circle")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
