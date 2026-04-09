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
                    showsStatusPicker: true,
                    tagDetail: nil,
                    tagActions: nil
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
            _ = try CreateAnimalUseCase(repository: repository).execute(input: input)
            dismiss()
        } catch {
            form.errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
