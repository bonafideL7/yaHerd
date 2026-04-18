import SwiftUI

struct FieldChecksView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var model = FieldChecksViewModel()

    private var repository: any FieldCheckRepository {
        dependencies.fieldCheckRepository
    }

    var body: some View {
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
                            FieldCheckSessionDetailView(sessionID: finding.sessionID)
                        } label: {
                            FieldCheckFindingRow(finding: finding, showsAnimalLink: false)
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
        .navigationTitle("Field Checks")
        .task {
            model.load(using: repository)
        }
        .refreshable {
            model.load(using: repository)
        }
        .alert("Can’t Load Checks", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
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
