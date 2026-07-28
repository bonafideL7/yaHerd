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
    @StateObject private var viewModel = WorkingTreatmentTemplatesViewModel(
        repository: EmptyWorkingRepository()
    )

    @State private var showingAdd = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        List {
            if viewModel.templates.isEmpty {
                ContentUnavailableView(
                    "No Treatment Templates",
                    systemImage: "list.bullet",
                    description: Text("Add a treatment template to reuse planned treatments during working sessions.")
                )
            } else {
                ForEach(viewModel.templates) { template in
                    NavigationLink {
                        TreatmentTemplateDetailView(templateID: template.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.headline)
                            Text(template.treatmentCount == 1 ? "1 treatment" : "\(template.treatmentCount) treatments")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .deleteDisabled(!dataAccessMode.allowsDataMutations)
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Treatment Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabledWhenDataReadOnly()
            }
        }
        .task {
            viewModel.configure(repository: repository)
            viewModel.load()
        }
        .onChange(of: showingAdd) { _, isPresented in
            if !isPresented {
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
            try repository.deleteTemplates(ids: offsets.map { viewModel.templates[$0].id })
            viewModel.load()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }
}

private struct TreatmentTemplateAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    private var repository: any WorkingTreatmentTemplateCreating {
        workingDependencies.treatmentTemplateCreator
    }

    @State private var name = ""
    @State private var plannedTreatments: [WorkingTreatmentPlanItem] = [
        WorkingTreatmentPlanItem(name: "")
    ]
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Template name", text: $name)
                }

                Section("Planned Treatments") {
                    ForEach($plannedTreatments) { $treatment in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Treatment", text: $treatment.name)
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
            .navigationTitle("New Treatment Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarSaveButton { save() }
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
            _ = try repository.createTemplate(name: trimmedName, items: cleanedTreatments)
            dismiss()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }
}

private struct TreatmentTemplateDetailView: View {
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    private var repository: any WorkingTreatmentTemplateEditorRepository {
        workingDependencies.treatmentTemplateEditorRepository
    }
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WorkingTreatmentTemplateDetailViewModel

    @State private var nameDraft = ""
    @State private var plannedTreatments: [WorkingTreatmentPlanItem] = []
    @State private var errorMessage: String?
    @State private var showingError = false

    init(templateID: UUID) {
        _viewModel = StateObject(
            wrappedValue: WorkingTreatmentTemplateDetailViewModel(
                templateID: templateID,
                repository: EmptyWorkingRepository()
            )
        )
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Template name", text: $nameDraft)
            }

            Section("Planned Treatments") {
                if plannedTreatments.isEmpty {
                    Text("No planned treatments")
                        .foregroundStyle(.secondary)
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
            }
        }
        .navigationTitle(nameDraft.isEmpty ? "Treatment Template" : nameDraft)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                ToolbarSaveButton { save() }
            }
            ToolbarItem(placement: .cancellationAction) {
                ToolbarCancelButton { dismiss() }
            }
        }
        .task {
            viewModel.configure(repository: repository)
            viewModel.load()
            seedFromSnapshot()
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
        guard let template = viewModel.template else { return }
        nameDraft = template.name
        plannedTreatments = template.plannedTreatments
    }

    private func save() {
        guard let template = viewModel.template else { return }
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
            try repository.updateTemplate(
                id: template.id,
                name: trimmedName,
                items: cleanedTreatments
            )
            dismiss()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }
}
