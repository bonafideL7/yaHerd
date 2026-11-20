//
//  TreatmentTemplatesView.swift
//  yaHerd
//

import SwiftUI

struct TreatmentTemplatesView: View {
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    private var repository: any WorkingTreatmentTemplatesRepository {
        workingDependencies.treatmentTemplatesRepository
    }
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(AppCurrentHerdSelection.self) private var herdSelection
    @StateObject private var viewModel = WorkingTreatmentTemplatesViewModel(
        repository: EmptyWorkingRepository()
    )

    @State private var showingAdd = false
    @State private var herdIdentity: WorkingQueueEditorHerdIdentity?
    @State private var errorMessage: String?
    @State private var showingError = false

    private var visibleTemplates: [WorkingTreatmentTemplateSummary] {
        viewModel.visibleTemplates(identity: herdIdentity, selection: herdSelection)
    }

    var body: some View {
        List {
            if visibleTemplates.isEmpty {
                ContentUnavailableView(
                    "No Treatments",
                    systemImage: "syringe",
                    description: Text("Save commonly used treatment sets for future working sessions.")
                )
            } else {
                ForEach(visibleTemplates) { template in
                    NavigationLink {
                        TreatmentTemplateDetailView(templateID: template.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.headline)
                            Text(template.treatmentCount == 1 ? "1 item" : "\(template.treatmentCount) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .deleteDisabled(
                        !dataAccessMode.allowsDataMutations ||
                        herdIdentity?.isCurrent(in: herdSelection) != true
                    )
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Treatments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabledWhenDataReadOnly()
                .disabled(herdIdentity?.isCurrent(in: herdSelection) != true)
            }
        }
        .task(id: herdSelection.selectionRevision) {
            // The list may remain mounted while the selected Herd changes.
            // Never retain A's rows while loading B's template inventory.
            viewModel.clear()
            herdIdentity = WorkingQueueEditorHerdIdentity(selection: herdSelection)
            guard herdIdentity?.isCurrent(in: herdSelection) == true else { return }
            viewModel.configure(repository: repository)
            viewModel.load()
        }
        .onChange(of: herdSelection.selectionRevision) { _, _ in
            showingAdd = false
            errorMessage = nil
            showingError = false
        }
        .onChange(of: showingAdd) { _, isPresented in
            if !isPresented, herdIdentity?.isCurrent(in: herdSelection) == true {
                viewModel.load()
            }
        }
        .alert("Can’t Save", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if newValue != nil { showingError = true }
        }
        .sheet(isPresented: $showingAdd) {
            TreatmentTemplateAddView()
        }
    }

    private func delete(at offsets: IndexSet) {
        do {
            guard try WorkingTreatmentTemplateHerdAction.performIfCurrent(
                identity: herdIdentity,
                selection: herdSelection,
                { try repository.deleteTemplates(ids: offsets.map { visibleTemplates[$0].id }) }
            ) != nil else { return }
            viewModel.load()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }
}

private struct TreatmentTemplateAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCurrentHerdSelection.self) private var herdSelection
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    private var repository: any WorkingTreatmentTemplateCreating {
        workingDependencies.treatmentTemplateCreator
    }

    @State private var name = ""
    @State private var herdIdentity: WorkingQueueEditorHerdIdentity?
    @State private var plannedTreatments: [WorkingTreatmentPlanItem] = [
        WorkingTreatmentPlanItem(name: "")
    ]
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Treatment set name", text: $name)
                }

                Section("Treatments") {
                    ForEach($plannedTreatments) { $treatment in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Vaccination, medication, or treatment", text: $treatment.name)
                            WorkingTreatmentDoseEditor(dose: $treatment.suggestedDose)
                        }
                    }
                    .onDelete { plannedTreatments.remove(atOffsets: $0) }

                    Button {
                        plannedTreatments.append(WorkingTreatmentPlanItem(name: ""))
                    } label: {
                        Label("Add Treatment", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("New Treatment Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarSaveButton { save() }
                        .disabled(herdIdentity?.isCurrent(in: herdSelection) != true)
                }
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
            }
            .alert("Can’t Save", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task {
            if herdIdentity == nil {
                herdIdentity = WorkingQueueEditorHerdIdentity(selection: herdSelection)
            }
        }
        .onChange(of: herdSelection.selectionRevision) { _, _ in
            dismiss()
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let cleanedTreatments = plannedTreatments
            .map {
                WorkingTreatmentPlanItem(
                    id: $0.id,
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    suggestedDose: $0.suggestedDose
                )
            }
            .filter { !$0.name.isEmpty }
        guard !cleanedTreatments.isEmpty else { return }

        do {
            guard try WorkingTreatmentTemplateHerdAction.performIfCurrent(
                identity: herdIdentity,
                selection: herdSelection,
                { try repository.createTemplate(name: trimmedName, items: cleanedTreatments) }
            ) != nil else { return }
            dismiss()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }
}

private struct TreatmentTemplateDetailView: View {
    @Environment(AppCurrentHerdSelection.self) private var herdSelection
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    private var repository: any WorkingTreatmentTemplateEditorRepository {
        workingDependencies.treatmentTemplateEditorRepository
    }
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WorkingTreatmentTemplateDetailViewModel

    @State private var nameDraft = ""
    @State private var herdIdentity: WorkingQueueEditorHerdIdentity?
    @State private var plannedTreatments: [WorkingTreatmentPlanItem] = []
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingDiscardConfirmation = false

    init(templateID: UUID) {
        _viewModel = StateObject(
            wrappedValue: WorkingTreatmentTemplateDetailViewModel(
                templateID: templateID,
                repository: EmptyWorkingRepository()
            )
        )
    }

    private var hasUnsavedChanges: Bool {
        guard let template = viewModel.visibleTemplate(
            identity: herdIdentity,
            selection: herdSelection
        ) else { return false }
        return nameDraft != template.name || plannedTreatments != template.plannedTreatments
    }

    var body: some View {
        Group {
            if herdIdentity?.isCurrent(in: herdSelection) == true {
                Form {
                    Section("Name") {
                        TextField("Treatment set name", text: $nameDraft)
                    }

                    Section("Treatments") {
                        if plannedTreatments.isEmpty {
                            Text("No treatments")
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
                    }
                }
            } else {
                ContentUnavailableView(
                    "Herd Changed",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Reopen this treatment set from the selected Herd.")
                )
            }
        }
        .navigationTitle(nameDraft.isEmpty ? "Treatment Set" : nameDraft)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasUnsavedChanges)
        .toolbar {
            if hasUnsavedChanges {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingDiscardConfirmation = true
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                ToolbarSaveButton { save() }
                    .disabled(herdIdentity?.isCurrent(in: herdSelection) != true)
            }
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Changes to this treatment set have not been saved.")
        }
        .task {
            if herdIdentity == nil {
                herdIdentity = WorkingQueueEditorHerdIdentity(selection: herdSelection)
            }
            guard herdIdentity?.isCurrent(in: herdSelection) == true else { return }
            viewModel.configure(repository: repository)
            viewModel.load()
            seedFromSnapshot()
        }
        .onChange(of: herdSelection.selectionRevision) { _, _ in
            viewModel.clear()
            nameDraft = ""
            plannedTreatments = []
            showingDiscardConfirmation = false
            dismiss()
        }
        .onChange(of: viewModel.template?.id) { _, _ in
            seedFromSnapshot()
        }
        .alert("Can’t Save", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? viewModel.errorMessage ?? "")
        }
    }

    private func seedFromSnapshot() {
        guard let template = viewModel.visibleTemplate(
            identity: herdIdentity,
            selection: herdSelection
        ) else { return }
        nameDraft = template.name
        plannedTreatments = template.plannedTreatments
    }

    private func save() {
        guard let template = viewModel.visibleTemplate(
            identity: herdIdentity,
            selection: herdSelection
        ) else { return }
        let trimmedName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let cleanedTreatments = plannedTreatments
            .map {
                WorkingTreatmentPlanItem(
                    id: $0.id,
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    suggestedDose: $0.suggestedDose
                )
            }
            .filter { !$0.name.isEmpty }
        guard !cleanedTreatments.isEmpty else { return }

        do {
            guard try WorkingTreatmentTemplateHerdAction.performIfCurrent(
                identity: herdIdentity,
                selection: herdSelection,
                {
                    try repository.updateTemplate(
                        id: template.id,
                        name: trimmedName,
                        items: cleanedTreatments
                    )
                }
            ) != nil else { return }
            dismiss()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }
}


/// A detached template editor must not write into whichever Herd is active later.
/// The synchronous repository call cannot be interrupted by an actor reentrancy.
@MainActor
enum WorkingTreatmentTemplateHerdAction {
    static func performIfCurrent<Result>(
        identity: WorkingQueueEditorHerdIdentity?,
        selection: AppCurrentHerdSelection,
        _ action: () throws -> Result
    ) rethrows -> Result? {
        guard identity?.isCurrent(in: selection) == true else { return nil }
        return try action()
    }
}
