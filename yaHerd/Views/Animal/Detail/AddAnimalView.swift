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

  private var availableStatusReferences: [AnimalStatusReference] {
    statusReferences
      .filter { $0.baseStatus == draft.status }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  var body: some View {
    NavigationStack {
      Form {
        AnimalFormView(
          name: $draft.name,
          tagNumber: $draft.tagNumber,
          tagColorID: $draft.tagColorID,
          sex: $draft.sex,
          birthDate: $draft.birthDate,
          status: $draft.status,
          pasture: $draft.pasture,
          sire: $draft.sire,
          dam: $draft.dam,
          distinguishingFeatures: $draft.distinguishingFeatures,
          activeParentPicker: $activeParentPicker,
          pastures: pastures
        )

        AnimalStatusEditorSection(
          status: $draft.status,
          statusReferenceID: $draft.statusReferenceID,
          saleDate: $draft.saleDate,
          salePriceText: $draft.salePriceText,
          reasonSold: $draft.reasonSold,
          deathDate: $draft.deathDate,
          causeOfDeath: $draft.causeOfDeath,
          availableStatusReferences: availableStatusReferences
        )
      }
      .navigationTitle("Add Animal")
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
    .sheet(item: $activeParentPicker) { picker in
      switch picker {
      case .sire:
        AnimalParentPickerView(
          title: "Select Sire",
          excludeAnimal: nil,
          suggestedSexes: [.male]
        ) { picked in
          draft.sire = picked.displayTagNumber
          activeParentPicker = nil
        }

      case .dam:
        AnimalParentPickerView(
          title: "Select Dam",
          excludeAnimal: nil,
          suggestedSexes: [.female]
        ) { picked in
          draft.dam = picked.displayTagNumber
          activeParentPicker = nil
        }
      }
    }
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
