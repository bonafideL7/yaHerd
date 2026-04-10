//
//  AddAnimalView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI

struct AddAnimalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var form = AnimalFormViewModel()
    @State private var activeParentPicker: ParentPickerType?
    @State private var showingError = false
    @State private var showingAddTag = false
    @State private var pendingTags: [AnimalTagSnapshot] = []

    private var repository: SwiftDataAnimalRepository {
        SwiftDataAnimalRepository(context: context)
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
                    pastures: form.pastureOptions,
                    statusReferences: form.statusReferenceOptions,
                    tagDetail: nil,
                    tagActions: nil,
                    pendingTags: $pendingTags,
                    onAddExistingTag: nil,
                    onAddPendingTag: { showingAddTag = true },
                    scrollTarget: nil
                )
            }
            .navigationTitle("Add Animal")
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
        .animalParentPickerSheet(
            activePicker: $activeParentPicker,
            sire: Binding(
                get: { form.draft.sire },
                set: { form.draft.sire = $0 }
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
}
