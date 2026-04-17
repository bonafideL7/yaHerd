import SwiftUI

struct FieldChecksView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var model = FieldChecksViewModel()

    private var repository: any FieldCheckRepository {
        dependencies.fieldCheckRepository
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    FieldCheckSessionSetupView()
                } label: {
                    Label("Start Pasture Check", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                }
            }

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
        .navigationTitle("Checks")
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

struct FieldCheckSessionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies

    @State private var model = FieldCheckSessionSetupViewModel()
    @State private var createdSessionID: UUID?
    @State private var navigateToCreatedSession = false
    @State private var selectedPastureID: UUID?
    @State private var countMode: FieldCheckCountMode = .individual
    @State private var title = ""
    @State private var startedAt: Date = .now
    @State private var notes = ""

    private let suggestedPastureID: UUID?

    init(suggestedPastureID: UUID? = nil) {
        self.suggestedPastureID = suggestedPastureID
        _selectedPastureID = State(initialValue: suggestedPastureID)
    }

    private var repository: any FieldCheckRepository {
        dependencies.fieldCheckRepository
    }

    private var selectedPastureName: String? {
        model.pastures.first(where: { $0.id == selectedPastureID })?.name
    }

    var body: some View {
        Form {
            Section("Session") {
                Picker("Pasture", selection: $selectedPastureID) {
                    Text("Select").tag(Optional<UUID>.none)
                    ForEach(model.pastures) { pasture in
                        Text(pasture.name).tag(Optional(pasture.id))
                    }
                }

                Picker("Count Method", selection: $countMode) {
                    ForEach(FieldCheckCountMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                LabeledContent("Method Notes") {
                    Text(countMode.description)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }

                TextField("Optional title", text: $title)
                DatePicker("Started", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
            }

            if let selectedPastureName {
                Section("Pasture") {
                    Text(selectedPastureName)
                }
            }

            Section("Notes") {
                TextField("Opening notes", text: $notes, axis: .vertical)
                    .lineLimit(3...5)
            }
        }
        .navigationTitle("Start Check")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToCreatedSession) {
            Group {
                if let createdSessionID {
                    FieldCheckSessionDetailView(sessionID: createdSessionID)
                } else {
                    EmptyView()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") {
                    startSession()
                }
                .disabled(selectedPastureID == nil)
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .task {
            model.load(using: repository)
            if selectedPastureID == nil {
                selectedPastureID = suggestedPastureID
            }
        }
        .alert("Can’t Start Check", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private func startSession() {
        do {
            createdSessionID = try model.createSession(
                pastureID: selectedPastureID,
                title: title,
                startedAt: startedAt,
                notes: notes,
                countMode: countMode,
                using: repository
            )
            navigateToCreatedSession = createdSessionID != nil
        } catch {
            model.errorMessage = error.localizedDescription
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
                    Text(session.title)
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

                if session.countMode != .observationOnly {
                    Label("\(session.totalSeen)/\(session.expectedHeadCountSnapshot)", systemImage: "number.circle")
                }

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
