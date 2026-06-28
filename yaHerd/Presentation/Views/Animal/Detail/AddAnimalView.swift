//
//  AddAnimalView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI

struct AddAnimalView: View {
    private let title: String
    @Environment(\.animalEditorRepository) private var repository
    @Environment(\.pastureReferenceDataReader) private var pastureReferenceDataReader
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: AddAnimalViewModel
    @State private var activeParentPicker: ParentPickerType?
    @State private var showingError = false
    @State private var showingAddTag = false
    @State private var editingPendingTag: AnimalTagSnapshot?
    
    init(
        title: String = "Add Animal",
        initialDraft: AnimalEditorDraft = AnimalEditorDraft(),
        editorContext: AnimalEditorContext = .standard
    ) {
        self.title = title
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
                    statusReferences: viewModel.form.statusReferenceOptions,
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarSaveButton { validateAndSave() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
            }
            .alert("Validation Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.form.errorMessage ?? viewModel.errorMessage ?? "")
            }
        }
        .task {
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
        .onChange(of: viewModel.form.errorMessage) { _, newValue in
            showingError = newValue != nil
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showingError = newValue != nil
        }
    }

    private func validateAndSave() {
        do {
            try viewModel.save(defaultTagColorID: tagColorLibrary.defaultColorID, using: repository)
            dismiss()
        } catch {
            viewModel.errorMessage = error.localizedDescription
            showingError = true
        }
    }

}
