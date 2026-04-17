//
//  AddAnimalView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI

struct AddAnimalView: View {
    private let title: String
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    @State private var form: AnimalFormViewModel
    @State private var activeParentPicker: ParentPickerType?
    @State private var showingError = false
    @State private var showingAddTag = false
    @State private var editingPendingTag: AnimalTagSnapshot?
    @State private var pendingTags: [AnimalTagSnapshot] = []


    init(
        title: String = "Add Animal",
        initialDraft: AnimalEditorDraft = AnimalEditorDraft(),
        editorContext: AnimalEditorContext = .standard
    ) {
        self.title = title
        _form = State(initialValue: AnimalFormViewModel(draft: initialDraft, context: editorContext))
    }

    private var repository: any AnimalRepository {
        dependencies.animalRepository
    }

    var body: some View {
        NavigationStack {
            Form {
                AnimalEditorSections(
                    draft: Binding(
                        get: { form.draft },
                        set: { form.draft = $0 }
                    ),
                    activeParentPicker: $activeParentPicker,
                    editorContext: form.context,
                    pastures: form.pastureOptions,
                    statusReferences: form.statusReferenceOptions,
                    tagDetail: nil,
                    tagActions: nil,
                    pendingTags: $pendingTags,
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
                    Button("Save") { validateAndSave() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
            .alert("Validation Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(form.errorMessage ?? "")
            }
        }
        .task {
            form.loadSupportData(using: repository)
        }
        .sheet(isPresented: $showingAddTag) {
            AnimalTagEditView(
                title: "Add Tag",
                saveButtonTitle: "Save",
                showsPrimaryToggle: true
            ) { number, colorID, isPrimary in
                addPendingTag(number: number, colorID: colorID, isPrimary: isPrimary)
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
                updatePendingTag(tagID: tag.id, number: number, colorID: colorID, isPrimary: isPrimary)
            }
            .presentationDetents([.medium, .large])
        }
        .animalParentPickerSheet(
            activePicker: $activeParentPicker,
            sireID: Binding(
                get: { form.draft.sireID },
                set: { form.draft.sireID = $0 }
            ),
            sire: Binding(
                get: { form.draft.sire },
                set: { form.draft.sire = $0 }
            ),
            damID: Binding(
                get: { form.draft.damID },
                set: { form.draft.damID = $0 }
            ),
            dam: Binding(
                get: { form.draft.dam },
                set: { form.draft.dam = $0 }
            ),
            excludeAnimalID: nil
        )
        .onChange(of: form.errorMessage) { _, newValue in
            showingError = newValue != nil
        }
    }

    private func validateAndSave() {
        do {
            let input = try form.makeInput()
            let created = try CreateAnimalUseCase(repository: repository).execute(input: input)

            for tag in pendingTags where !tag.isPrimary {
                _ = try AddAnimalTagUseCase(repository: repository).execute(
                    animalID: created.id,
                    input: AnimalTagInput(
                        number: tag.normalizedNumber,
                        colorID: tag.colorID,
                        isPrimary: false
                    )
                )
            }

            dismiss()
        } catch {
            form.errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func addPendingTag(number: String, colorID: UUID?, isPrimary: Bool) {
        let normalizedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNumber.isEmpty else { return }

        let shouldBePrimary = isPrimary || pendingTags.isEmpty

        if shouldBePrimary {
            pendingTags = pendingTags.map { tag in
                AnimalTagSnapshot(
                    id: tag.id,
                    number: tag.number,
                    colorID: tag.colorID,
                    isPrimary: false,
                    isActive: tag.isActive,
                    assignedAt: tag.assignedAt,
                    removedAt: tag.removedAt
                )
            }
        }

        pendingTags.append(
            AnimalTagSnapshot(
                id: UUID(),
                number: normalizedNumber,
                colorID: colorID,
                isPrimary: shouldBePrimary,
                isActive: true,
                assignedAt: .now,
                removedAt: nil
            )
        )

        if let primary = pendingTags.first(where: { $0.isPrimary }) {
            form.draft.tagNumber = primary.normalizedNumber
            form.draft.tagColorID = primary.colorID
        }
    }
    private func updatePendingTag(tagID: UUID, number: String, colorID: UUID?, isPrimary: Bool) {
        let normalizedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNumber.isEmpty else { return }

        let shouldBePrimary = isPrimary || pendingTags.filter({ $0.id != tagID }).isEmpty

        pendingTags = pendingTags.map { tag in
            AnimalTagSnapshot(
                id: tag.id,
                number: tag.id == tagID ? normalizedNumber : tag.number,
                colorID: tag.id == tagID ? colorID : tag.colorID,
                isPrimary: tag.id == tagID ? shouldBePrimary : (shouldBePrimary ? false : tag.isPrimary),
                isActive: tag.isActive,
                assignedAt: tag.assignedAt,
                removedAt: tag.removedAt
            )
        }

        syncPendingPrimaryTagToDraft()
    }

    private func syncPendingPrimaryTagToDraft() {
        if let primary = pendingTags.first(where: { $0.isPrimary }) {
            form.draft.tagNumber = primary.normalizedNumber
            form.draft.tagColorID = primary.colorID
        } else {
            form.draft.tagNumber = ""
            form.draft.tagColorID = nil
        }
    }

}
