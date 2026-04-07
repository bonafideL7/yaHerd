//
//  AddAnimalView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftData
import SwiftUI

struct AddAnimalView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss

  @Query(sort: \Pasture.name) private var pastures: [Pasture]
  @Query(sort: \AnimalStatusReference.name) private var statusReferences: [AnimalStatusReference]

  @State private var draft = AnimalEditorDraft()
  @State private var activeParentPicker: ParentPickerType?
  @State private var errorMessage: String?
  @State private var showingError = false

  var body: some View {
    NavigationStack {
      Form {
        AnimalEditorSections(
          draft: $draft,
          activeParentPicker: $activeParentPicker,
          pastures: pastures,
          statusReferences: statusReferences,
          showsStatusPicker: true
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
        Text(errorMessage ?? "")
      }
    }
    .animalParentPickerSheet(
      activePicker: $activeParentPicker,
      sire: $draft.sire,
      dam: $draft.dam,
      excludeAnimal: nil
    )
  }

  private func validateAndSave() {
    do {
      let animal = try draft.makeAnimal()
      context.insert(animal)

      if !animal.tagNumber.isEmpty {
        _ = animal.ensurePrimaryTagRecord()
      }

      try context.save()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
      showingError = true
    }
  }
}
