import SwiftUI

struct FieldCheckSessionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldCheckFeatureDependencies) private var fieldCheckDependencies
    private var setupRepository: any FieldCheckSessionSetupRepository { fieldCheckDependencies.sessionSetupRepository }
    private var pastureReferenceDataReader: any PastureReferenceDataReader { fieldCheckDependencies.pastureReferenceReader }
    @Environment(\.appDataAccessMode) private var dataAccessMode

    @State private var model = FieldCheckSessionSetupViewModel()
    @State private var selectedPastureID: UUID?
    @State private var startedAt: Date = .now
    @State private var notes = ""
    @State private var startedRoute: StartedFieldCheckRoute?
    @State private var isStartingSession = false

    private let suggestedPastureID: UUID?
    private let onSessionStarted: ((UUID) -> Void)?

    init(suggestedPastureID: UUID? = nil, onSessionStarted: ((UUID) -> Void)? = nil) {
        self.suggestedPastureID = suggestedPastureID
        self.onSessionStarted = onSessionStarted
        _selectedPastureID = State(initialValue: suggestedPastureID)
    }

    private var selectedPasture: PastureOption? {
        guard let selectedPastureID else { return nil }
        return model.pastures.first { $0.id == selectedPastureID }
    }

    private var canStart: Bool {
        dataAccessMode.allowsDataMutations && selectedPasture != nil && !isStartingSession
    }

    private var startStatusText: String? {
        if isStartingSession {
            return "Starting check…"
        }

        if !dataAccessMode.allowsDataMutations {
            return "Recovery mode is read-only. New checks cannot be saved."
        }

        if !model.hasLoaded {
            return "Loading pastures…"
        }

        if model.pastures.isEmpty {
            return "Add a pasture before starting a check."
        }

        if selectedPasture == nil {
            return "Select a pasture to start."
        }

        return nil
    }

    var body: some View {
        Form {
            startDetailsSection
            workflowPreviewSection
        }
        .disabled(isStartingSession)
        .navigationTitle("Start Pasture Check")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isStartingSession)
        .interactiveDismissDisabled(isStartingSession)
        .task {
            if !model.hasLoaded {
                model.load(using: pastureReferenceDataReader)
            }

            if selectedPastureID == nil {
                selectedPastureID = suggestedPastureID
            }
        }
        .navigationDestination(item: $startedRoute) { route in
            FieldCheckSessionDetailView(sessionID: route.id)
        }
        .safeAreaInset(edge: .bottom) {
            FieldCheckStartBar(
                isEnabled: canStart,
                statusText: startStatusText,
                onStart: startSession
            )
        }
        .alert("Can’t Start Check", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var startDetailsSection: some View {
        Section {
            if !model.hasLoaded {
                HStack {
                    ProgressView()
                    Text("Loading pastures…")
                        .foregroundStyle(.secondary)
                }
            } else if model.pastures.isEmpty {
                ContentUnavailableView(
                    "No Pastures",
                    systemImage: "map",
                    description: Text("Add a pasture before starting a pasture check.")
                )
            } else {
                LabeledContent("Pasture") {
                    Picker("Pasture", selection: $selectedPastureID) {
                        Text("Select").tag(Optional<UUID>.none)
                        ForEach(model.pastures) { pasture in
                            Text(pasture.name).tag(Optional(pasture.id))
                        }
                    }
                    .labelsHidden()
                }
            }

            LabeledContent("Started") {
                DatePicker(
                    "Started",
                    selection: $startedAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
            }

            TextField("Opening notes", text: $notes, axis: .vertical)
                .lineLimit(3...5)
        } header: {
            Text("Check Details")
        } footer: {
            Text("Start the check here, then verify the roster, count animals, record findings, and add notes in the check workflow.")
        }
    }

    private var workflowPreviewSection: some View {
        Section {
            FieldCheckSetupWorkflowRow(title: "Roster", value: "Verify animals by tag", systemImage: "tag")
            FieldCheckSetupWorkflowRow(title: "Count", value: "Use a fast count by type", systemImage: "plus.forwardslash.minus")
            FieldCheckSetupWorkflowRow(title: "Findings", value: "Record issues or missing animals", systemImage: "exclamationmark.bubble")
            FieldCheckSetupWorkflowRow(title: "Notes", value: "Add session notes", systemImage: "note.text")
        } header: {
            Text("After Start")
        } footer: {
            Text("The check opens directly into field-work mode after it is created.")
        }
    }

    private func startSession() {
        guard dataAccessMode.allowsDataMutations,
              !isStartingSession,
              let pastureID = selectedPasture?.id else {
            return
        }

        isStartingSession = true
        let sessionStartedAt = startedAt
        let openingNotes = notes

        Task { @MainActor in
            defer { isStartingSession = false }

            do {
                let sessionID = try await model.createSession(
                    pastureID: pastureID,
                    startedAt: sessionStartedAt,
                    notes: openingNotes,
                    using: setupRepository
                )
                if let onSessionStarted {
                    dismiss()
                    onSessionStarted(sessionID)
                } else {
                    startedRoute = StartedFieldCheckRoute(id: sessionID)
                }
            } catch {
                model.errorMessage = UserVisibleErrorMessage.make(error)
            }
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

private struct FieldCheckSetupWorkflowRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct FieldCheckStartBar: View {
    let isEnabled: Bool
    let statusText: String?
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let statusText {
                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Button(action: onStart) {
                Label("Start Check", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }
}

private struct StartedFieldCheckRoute: Identifiable, Hashable {
    let id: UUID
}
