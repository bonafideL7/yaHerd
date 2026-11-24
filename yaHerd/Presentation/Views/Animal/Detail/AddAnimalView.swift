//
//  AddAnimalView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI

struct AddAnimalView: View {
    private let title: String
    private let onSave: (@MainActor (AnimalDetailSnapshot) async throws -> Void)?
    @Environment(\.animalFeatureDependencies) private var animalDependencies
    private var repository: any AnimalEditorRepository { animalDependencies.editorRepository }
    private var pastureReferenceDataReader: any PastureReferenceDataReader { animalDependencies.pastureReferenceReader }
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCurrentHerdSelection.self) private var herdSelection

    @State private var viewModel: AddAnimalViewModel
    @State private var activeParentPicker: ParentPickerType?
    @State private var showingError = false
    @State private var showingAddTag = false
    @State private var editingPendingTag: AnimalTagSnapshot?
    @State private var isSaving = false
    @State private var pendingCreatedAnimal: AnimalDetailSnapshot?
    @State private var saveTask: Task<Void, Never>?
    
    init(
        title: String = "Add Animal",
        initialDraft: AnimalEditorDraft = AnimalEditorDraft(),
        editorContext: AnimalEditorContext = .standard,
        onSave: (@MainActor (AnimalDetailSnapshot) async throws -> Void)? = nil
    ) {
        self.title = title
        self.onSave = onSave
        _viewModel = State(initialValue: AddAnimalViewModel(initialDraft: initialDraft, editorContext: editorContext))
    }


    var body: some View {
        NavigationStack {
            Form {
                AnimalEditorSections(
                    draft: Binding(
                        get: { viewModel.form.draft },
                        set: { viewModel.form.draft = $0 }
                    ),
                    activeParentPicker: $activeParentPicker,
                    editorContext: viewModel.form.context,
                    pastures: viewModel.form.pastureOptions,
                    tagDetail: nil,
                    tagActions: nil,
                    pendingTags: Binding(
                        get: { viewModel.pendingTags },
                        set: { viewModel.pendingTags = $0 }
                    ),
                    onAddExistingTag: nil,
                    onEditExistingTag: nil,
                    onAddPendingTag: { showingAddTag = true },
                    onEditPendingTag: { editingPendingTag = $0 },
                    draftTags: nil,
                    draftTagActions: nil,
                    onAddDraftTag: nil,
                    onEditDraftTag: nil,
                    scrollTarget: nil
                )
            }
            .disabled(isSaving || pendingCreatedAnimal != nil)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarSaveButton { validateAndSave() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                        .disabled(isSaving)
                }
            }
            .alert("Validation Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.form.errorMessage ?? viewModel.errorMessage ?? "")
            }
        }
        .task(id: animalDependencies.mutationStream.animalRevision) {
            viewModel.loadSupportData(using: repository, pastureRepository: pastureReferenceDataReader)
        }
        .sheet(isPresented: $showingAddTag) {
            AnimalTagEditView(
                title: "Add Tag",
                saveButtonTitle: "Save",
                showsPrimaryToggle: true
            ) { number, colorID, isPrimary in
                viewModel.addPendingTag(number: number, colorID: colorID, isPrimary: isPrimary, defaultTagColorID: tagColorLibrary.defaultColorID)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingPendingTag) { tag in
            AnimalTagEditView(
                initialNumber: tag.normalizedNumber,
                initialColorID: tag.colorID,
                initialIsPrimary: tag.isPrimary,
                title: "Edit Tag",
                saveButtonTitle: "Save",
                showsPrimaryToggle: true
            ) { number, colorID, isPrimary in
                viewModel.updatePendingTag(tagID: tag.id, number: number, colorID: colorID, isPrimary: isPrimary, defaultTagColorID: tagColorLibrary.defaultColorID)
            }
            .presentationDetents([.medium, .large])
        }
        .animalParentPickerSheet(
            activePicker: $activeParentPicker,
            sireID: Binding(
                get: { viewModel.form.draft.sireID },
                set: { viewModel.form.draft.sireID = $0 }
            ),
            sire: Binding(
                get: { viewModel.form.draft.sire },
                set: { viewModel.form.draft.sire = $0 }
            ),
            damID: Binding(
                get: { viewModel.form.draft.damID },
                set: { viewModel.form.draft.damID = $0 }
            ),
            dam: Binding(
                get: { viewModel.form.draft.dam },
                set: { viewModel.form.draft.dam = $0 }
            ),
            excludeAnimalID: nil
        )
        .onChange(of: herdSelection.selectionRevision) { _, _ in
            saveTask?.cancel()
        }
        .onDisappear {
            saveTask?.cancel()
        }
        .onChange(of: viewModel.form.errorMessage) { _, newValue in
            showingError = newValue != nil
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showingError = newValue != nil
        }
    }

    private func validateAndSave() {
        guard !isSaving, let originatingHerdID = herdSelection.currentHerdID else { return }
        let originatingSelectionRevision = herdSelection.selectionRevision
        isSaving = true

        saveTask = Task { @MainActor in
            defer {
                isSaving = false
                saveTask = nil
            }

            do {
                try Task.checkCancellation()
                guard herdSelection.currentHerdID == originatingHerdID,
                      herdSelection.selectionRevision == originatingSelectionRevision else {
                    throw CancellationError()
                }

                let createdAnimal: AnimalDetailSnapshot
                if let pendingCreatedAnimal {
                    createdAnimal = pendingCreatedAnimal
                } else {
                    createdAnimal = try viewModel.save(
                        defaultTagColorID: tagColorLibrary.defaultColorID,
                        using: repository,
                        expectedHerdID: originatingHerdID,
                        expectedSelectionRevision: originatingSelectionRevision,
                        selection: herdSelection
                    )
                    pendingCreatedAnimal = createdAnimal
                }

                try Task.checkCancellation()
                guard herdSelection.currentHerdID == originatingHerdID,
                      herdSelection.selectionRevision == originatingSelectionRevision else {
                    throw CancellationError()
                }
                try await onSave?(createdAnimal)

                try Task.checkCancellation()
                guard herdSelection.currentHerdID == originatingHerdID,
                      herdSelection.selectionRevision == originatingSelectionRevision else {
                    throw CancellationError()
                }
                pendingCreatedAnimal = nil
                dismiss()
            } catch is CancellationError {
                // A stale view must not create or navigate within another Herd.
            } catch {
                guard !Task.isCancelled,
                      herdSelection.currentHerdID == originatingHerdID,
                      herdSelection.selectionRevision == originatingSelectionRevision else {
                    return
                }
                viewModel.errorMessage = UserVisibleErrorMessage.make(error)
                showingError = true
            }
        }
    }

}
