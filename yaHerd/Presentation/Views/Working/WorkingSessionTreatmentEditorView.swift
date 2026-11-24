import SwiftUI

struct WorkingSessionTreatmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(AppCurrentHerdSelection.self) private var herdSelection

    private var repository: any WorkingSessionDetailRepository {
        workingDependencies.sessionDetailRepository
    }

    private let sessionID: UUID
    private let initialTreatments: [WorkingTreatmentPlanItem]

    @State private var plannedTreatments: [WorkingTreatmentPlanItem]
    @State private var isSaving = false
    @State private var planChanged = false
    @State private var showingDiscardConfirmation = false
    @State private var showingError = false
    @State private var errorMessage: String?
    @State private var editorHerdIdentity: WorkingQueueEditorHerdIdentity?

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
            && editorHerdIdentity?.isCurrent(in: herdSelection) == true
            && !isSaving
            && !planChanged
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
        .onChange(of: workingDependencies.mutationStream.workingSessionRevision) { _, _ in
            guard editorHerdIdentity?.isCurrent(in: herdSelection) == true, !isSaving else { return }
            do {
                guard let session = try repository.fetchSessionDetail(id: sessionID),
                      session.status == .active, session.plannedTreatments == initialTreatments else {
                    planChanged = true
                    errorMessage = "This session or its treatment plan changed. Your draft is retained; reopen the editor before saving."
                    showingError = true
                    return
                }
                planChanged = false
            } catch {
                planChanged = true
                errorMessage = UserVisibleErrorMessage.make(error)
                showingError = true
            }
        }
        .task {
            // Bind a presented editor to one Herd selection generation.
            // Returning to that same UUID must not revive an old draft.
            if editorHerdIdentity == nil {
                editorHerdIdentity = WorkingQueueEditorHerdIdentity(selection: herdSelection)
            }
        }
    }

    private func save() {
        guard canSave,
              let editorHerdIdentity else { return }

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
                let saved = try await WorkingSessionTreatmentPlanSave.execute(
                    sessionID: sessionID,
                    initialTreatments: initialTreatments,
                    updatedTreatments: updatedTreatments,
                    editorIdentity: editorHerdIdentity,
                    selection: herdSelection,
                    repository: repository
                )
                guard saved else { return }
                dismiss()
            } catch {
                guard !Task.isCancelled,
                      editorHerdIdentity.isCurrent(in: herdSelection) else { return }
                errorMessage = UserVisibleErrorMessage.make(error)
                showingError = true
            }
        }
    }
}

/// Applies the treatment-plan version check and mutation against the exact
/// Herd selection that opened the editor. Persistence remains repository-owned.
@MainActor
enum WorkingSessionTreatmentPlanSave {
    enum ValidationError: LocalizedError, Equatable {
        case inactiveSession
        case treatmentsChanged

        var errorDescription: String? {
            switch self {
            case .inactiveSession:
                "This working session is no longer active."
            case .treatmentsChanged:
                "This session's treatments changed while editing. Close and reopen the editor to review the latest plan."
            }
        }
    }

    static func execute(
        sessionID: UUID,
        initialTreatments: [WorkingTreatmentPlanItem],
        updatedTreatments: [WorkingTreatmentPlanItem],
        editorIdentity: WorkingQueueEditorHerdIdentity,
        selection: AppCurrentHerdSelection,
        repository: any WorkingSessionDetailRepository
    ) async throws -> Bool {
        guard !Task.isCancelled,
              editorIdentity.isCurrent(in: selection) else { return false }

        guard let currentSession = try repository.fetchSessionDetail(id: sessionID),
              currentSession.status == .active else {
            throw ValidationError.inactiveSession
        }
        guard currentSession.plannedTreatments == initialTreatments else {
            throw ValidationError.treatmentsChanged
        }

        guard !Task.isCancelled,
              editorIdentity.isCurrent(in: selection) else { return false }
        try await repository.updateSessionTreatments(
            id: sessionID,
            plannedTreatments: updatedTreatments
        )
        // A save may commit during a Herd switch. Do not dismiss/publish the
        // result into a different Herd or a later selection of the same UUID.
        return !Task.isCancelled && editorIdentity.isCurrent(in: selection)
    }
}
