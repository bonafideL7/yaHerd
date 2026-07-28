//
//  NewWorkingSessionView.swift
//  yaHerd
//

import SwiftUI

struct NewWorkingSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    private var repository: any NewWorkingSessionRepository { workingDependencies.newSessionRepository }
    private var pastureRepository: any PastureReferenceDataReader { workingDependencies.pastureReferenceReader }
    private var animalSummaryReader: any AnimalSummaryReading { workingDependencies.animalSummaryReader }

    @StateObject private var viewModel = NewWorkingSessionViewModel(
        pastureRepository: EmptyPastureRepository(),
        animalSummaryReader: EmptyAnimalRepository(),
        workingRepository: EmptyWorkingRepository()
    )

    @State private var date: Date = .now
    @State private var selectedPastureID: UUID?
    @State private var selectedTemplateID: UUID?
    @State private var selectedTemplateName: String?
    @State private var plannedTreatments: [WorkingTreatmentPlanItem] = []
    @State private var specifiesAnimals = false
    @State private var selectedAnimalIDs: Set<UUID> = []
    @State private var showingAnimalPicker = false
    @State private var startedRoute: StartedWorkingSessionSetupRoute?

    private let suggestedPastureID: UUID?
    private let wrapsInNavigationStack: Bool
    private let onSessionCreated: ((UUID) -> Void)?

    init(
        suggestedPastureID: UUID? = nil,
        wrapsInNavigationStack: Bool = true,
        onSessionCreated: ((UUID) -> Void)? = nil
    ) {
        self.suggestedPastureID = suggestedPastureID
        self.wrapsInNavigationStack = wrapsInNavigationStack
        self.onSessionCreated = onSessionCreated
        _selectedPastureID = State(initialValue: suggestedPastureID)
    }

    private var selectedPasture: PastureOption? {
        guard let selectedPastureID else { return nil }
        return viewModel.pastures.first { $0.id == selectedPastureID }
    }

    private var eligibleAnimals: [AnimalSummary] {
        viewModel.eligibleAnimals(pastureID: selectedPastureID)
    }

    private var includedAnimalCount: Int {
        specifiesAnimals ? selectedAnimalIDs.count : eligibleAnimals.count
    }

    private var canStart: Bool {
        dataAccessMode.allowsDataMutations
            && selectedPasture != nil
            && includedAnimalCount > 0
    }

    private var startStatusText: String? {
        if !dataAccessMode.allowsDataMutations {
            return "Recovery mode is read-only. New sessions cannot be saved."
        }
        if !viewModel.hasLoaded {
            return "Loading pastures and animals…"
        }
        if viewModel.pastures.isEmpty {
            return "Add a pasture before starting a working session."
        }
        if selectedPasture == nil {
            return "Select a pasture to start."
        }
        if eligibleAnimals.isEmpty {
            return "The selected pasture has no active animals available to work."
        }
        if specifiesAnimals && selectedAnimalIDs.isEmpty {
            return "Select at least one animal."
        }
        return nil
    }

    var body: some View {
        if wrapsInNavigationStack {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        Form {
            sessionSection
            animalsSection
            treatmentsSection
        }
        .navigationTitle("Start Working Session")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(
                pastureRepository: pastureRepository,
                animalSummaryReader: animalSummaryReader,
                workingRepository: repository
            )
            if !viewModel.hasLoaded { viewModel.load() }
            seedSuggestedPastureIfNeeded()
            resetAnimalSelection()
        }
        .onChange(of: selectedPastureID) { _, _ in resetAnimalSelection() }
        .sheet(isPresented: $showingAnimalPicker) {
            WorkingSessionAnimalSelectionView(animals: eligibleAnimals, selection: $selectedAnimalIDs)
        }
        .navigationDestination(item: $startedRoute) { route in
            WorkingSessionDetailView(sessionID: route.id)
        }
        .safeAreaInset(edge: .bottom) {
            WorkingSessionStartBar(
                animalCount: includedAnimalCount,
                isEnabled: canStart,
                statusText: startStatusText,
                onStart: startSession
            )
        }
        .toolbar {
            if wrapsInNavigationStack {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
            }
        }
        .alert("Can’t Start Session", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var sessionSection: some View {
        Section("Session") {
            if !viewModel.hasLoaded {
                HStack {
                    ProgressView()
                    Text("Loading pastures…").foregroundStyle(.secondary)
                }
            } else if viewModel.pastures.isEmpty {
                ContentUnavailableView(
                    "No Pastures",
                    systemImage: "map",
                    description: Text("Add a pasture before starting a working session.")
                )
            } else {
                LabeledContent("Pasture") {
                    Picker("Pasture", selection: $selectedPastureID) {
                        Text("Select").tag(Optional<UUID>.none)
                        ForEach(viewModel.pastures) { pasture in
                            Text(pasture.name).tag(Optional(pasture.id))
                        }
                    }
                    .labelsHidden()
                }
            }

            LabeledContent("Date") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }

    private var animalsSection: some View {
        Section {
            LabeledContent("Included") {
                Text(specifiesAnimals ? "Selected animals" : "All animals")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Available") {
                Text("\(eligibleAnimals.count)").foregroundStyle(.secondary)
            }
            Toggle("Specify Animals", isOn: $specifiesAnimals)
                .onChange(of: specifiesAnimals) { _, enabled in
                    if enabled { selectedAnimalIDs = Set(eligibleAnimals.map(\.id)) }
                }
            if specifiesAnimals {
                Button { showingAnimalPicker = true } label: {
                    HStack {
                        Label("Choose Animals", systemImage: "checklist")
                        Spacer()
                        Text("\(selectedAnimalIDs.count) selected").foregroundStyle(.secondary)
                    }
                }
                .disabled(eligibleAnimals.isEmpty)
            }
        } header: {
            Text("Animals")
        } footer: {
            Text("All active animals in the selected pasture are included automatically unless you choose a specific group.")
        }
    }

    private var treatmentsSection: some View {
        Section {
            Picker("Treatment Template", selection: $selectedTemplateID) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(viewModel.templates) { template in
                    Text(template.name).tag(Optional(template.id))
                }
            }
            .onChange(of: selectedTemplateID) { _, id in applyTemplate(id: id) }

            if plannedTreatments.isEmpty {
                Text("No planned treatments").foregroundStyle(.secondary)
            } else {
                ForEach($plannedTreatments) { $treatment in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Treatment", text: $treatment.name)
                        WorkingTreatmentDoseEditor(dose: $treatment.suggestedDose)
                    }
                }
                .onDelete { plannedTreatments.remove(atOffsets: $0) }
            }

            Button {
                plannedTreatments.append(WorkingTreatmentPlanItem(name: ""))
            } label: {
                Label("Add Treatment", systemImage: "plus")
            }
        } header: {
            Text("Treatments")
        } footer: {
            Text("Treatments are optional. Suggested dose amount, unit, and route can be adjusted for each animal during the session.")
        }
    }

    private func seedSuggestedPastureIfNeeded() {
        guard let suggestedPastureID else { return }
        selectedPastureID = viewModel.pastures.contains(where: { $0.id == suggestedPastureID })
            ? suggestedPastureID : nil
    }

    private func resetAnimalSelection() {
        selectedAnimalIDs = specifiesAnimals ? Set(eligibleAnimals.map(\.id)) : []
    }

    private func applyTemplate(id: UUID?) {
        guard let id, let template = viewModel.templateDetail(id: id) else {
            selectedTemplateName = nil
            plannedTreatments = []
            return
        }
        selectedTemplateName = template.name
        plannedTreatments = template.plannedTreatments
    }

    private func startSession() {
        guard dataAccessMode.allowsDataMutations, let pastureID = selectedPastureID else { return }
        let cleanedTreatments = plannedTreatments
            .map {
                WorkingTreatmentPlanItem(
                    id: $0.id,
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    suggestedDose: $0.suggestedDose
                )
            }
            .filter { !$0.name.isEmpty }

        do {
            let sessionID = try viewModel.startSession(
                date: date,
                pastureID: pastureID,
                treatmentTemplateName: selectedTemplateName,
                plannedTreatments: cleanedTreatments,
                animalIDs: specifiesAnimals ? Array(selectedAnimalIDs) : nil
            )
            if let onSessionCreated {
                dismiss()
                onSessionCreated(sessionID)
            } else {
                startedRoute = StartedWorkingSessionSetupRoute(id: sessionID)
            }
        } catch {
            viewModel.errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}
