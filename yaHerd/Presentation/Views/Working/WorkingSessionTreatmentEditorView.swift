import SwiftUI

struct WorkingSessionTreatmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    @Environment(\.appDataAccessMode) private var dataAccessMode

    private var repository: any WorkingSessionDetailRepository {
        workingDependencies.sessionDetailRepository
    }

    private let sessionID: UUID
    private let initialTreatments: [WorkingTreatmentPlanItem]

    @State private var plannedTreatments: [WorkingTreatmentPlanItem]
    @State private var isSaving = false
    @State private var showingDiscardConfirmation = false
    @State private var showingError = false
    @State private var errorMessage: String?

    init(session: WorkingSessionDetailSnapshot) {
        sessionID = session.id
        initialTreatments = session.plannedTreatments
        _plannedTreatments = State(initialValue: session.plannedTreatments)
    }

    private var hasUnsavedChanges: Bool {
        plannedTreatments != initialTreatments
    }

    private var canSave: Bool {
        dataAccessMode.allowsDataMutations
            && !isSaving
            && hasUnsavedChanges
            && plannedTreatments.allSatisfy {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if plannedTreatments.isEmpty {
                        Text("No planned treatments")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($plannedTreatments) { $treatment in
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Vaccination, medication, or treatment", text: $treatment.name)
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
                    .disabled(isSaving || !dataAccessMode.allowsDataMutations)
                } header: {
                    Text("Vaccinations & Treatments")
                } footer: {
                    Text("These are defaults for animals worked after the change. Editing this plan does not erase treatments already recorded for animals.")
                }
            }
            .disabled(isSaving || !dataAccessMode.allowsDataMutations)
            .navigationTitle("Edit Treatments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton {
                        if hasUnsavedChanges {
                            showingDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarSaveButton { save() }
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges || isSaving)
            .confirmationDialog(
                "Discard treatment changes?",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Unsaved changes to this session's treatment plan will be lost.")
            }
            .alert("Can't Update Treatments", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func save() {
        guard canSave else { return }

        let updatedTreatments = plannedTreatments.map {
            WorkingTreatmentPlanItem(
                id: $0.id,
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                suggestedDose: $0.suggestedDose
            )
        }

        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }

            do {
                guard let currentSession = try repository.fetchSessionDetail(id: sessionID),
                      currentSession.status == .active else {
                    errorMessage = "This working session is no longer active."
                    showingError = true
                    return
                }

                guard currentSession.plannedTreatments == initialTreatments else {
                    errorMessage = "This session's treatments changed while editing. Close and reopen the editor to review the latest plan."
                    showingError = true
                    return
                }

                try await repository.updateSessionTreatments(
                    id: sessionID,
                    plannedTreatments: updatedTreatments
                )
                dismiss()
            } catch {
                errorMessage = UserVisibleErrorMessage.make(error)
                showingError = true
            }
        }
    }
}
