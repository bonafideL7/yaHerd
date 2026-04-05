//
//  AnimalDetailView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftData
import SwiftUI

struct AnimalDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
  @AppStorage("allowHardDelete") private var hardDeleteOnSwipe = false

  @State private var draft: AnimalEditorDraft
  @State private var isEditing = false
  @State private var activeParentPicker: ParentPickerType?
  @State private var showingAddTag = false
  @State private var showingArchiveConfirmation = false
  @State private var showingHardDeleteConfirmation = false
  @State private var showingSaveError = false
  @State private var saveErrorMessage = ""

  let animal: Animal

  @Query(sort: \Pasture.name) private var pastures: [Pasture]
  @Query(sort: \AnimalStatusReference.name) private var statusReferences: [AnimalStatusReference]

  init(animal: Animal) {
    self.animal = animal
    _draft = State(initialValue: AnimalEditorDraft(animal: animal))
  }

  private var draftStatusReferences: [AnimalStatusReference] {
    statusReferences
      .filter { $0.baseStatus == draft.status }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private var displayedStatus: AnimalStatus {
    isEditing ? draft.status : animal.status
  }

  private var selectedStatusReference: AnimalStatusReference? {
    let statusReferenceID = isEditing ? draft.statusReferenceID : animal.statusReferenceID
    guard let statusReferenceID else { return nil }
    return statusReferences.first(where: { $0.id == statusReferenceID })
  }

  private var displayedTagNumber: String {
    isEditing ? draft.normalizedTagNumber : animal.displayTagNumber
  }

  private var displayedTagColorID: UUID? {
    isEditing ? draft.tagColorID : animal.displayTagColorID
  }

  var body: some View {
    Form {
      if isEditing {
        editingContent
      } else {
        readOnlyContent
      }
    }
    .sheet(item: $activeParentPicker) { picker in
      switch picker {
      case .sire:
        AnimalParentPickerView(
          title: "Select Sire",
          excludeAnimal: animal,
          suggestedSexes: [.male]
        ) { picked in
          draft.sire = picked.displayTagNumber
          activeParentPicker = nil
        }

      case .dam:
        AnimalParentPickerView(
          title: "Select Dam",
          excludeAnimal: animal,
          suggestedSexes: [.female]
        ) { picked in
          draft.dam = picked.displayTagNumber
          activeParentPicker = nil
        }
      }
    }
    .sheet(isPresented: $showingAddTag) {
      AnimalTagEditView { number, colorID, isPrimary in
        _ = animal.addTag(number: number, colorID: colorID, isPrimary: isPrimary)
        saveContext()
        showingAddTag = false
      }
      .presentationDetents([.medium, .large])
    }
    .confirmationDialog(
      "Archive this record?", isPresented: $showingArchiveConfirmation, titleVisibility: .visible
    ) {
      Button("Archive Record", role: .destructive) {
        animal.archive()
        saveContext()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Archived records are hidden from normal herd views but can be restored later.")
    }
    .confirmationDialog(
      "Permanently delete this animal?", isPresented: $showingHardDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete Permanently", role: .destructive) {
        context.delete(animal)
        saveContext()
        dismiss()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes the animal and all related records from the app.")
    }
    .alert("Can’t Save", isPresented: $showingSaveError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(saveErrorMessage)
    }
    .navigationTitle("Animal")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(isEditing)
    .toolbar {
      if !displayedTagNumber.isEmpty {
        ToolbarItem(placement: .principal) {
          let def =
            tagColorLibrary.definition(for: displayedTagColorID) ?? tagColorLibrary.defaultColor
          AnimalTagView(
            tagNumber: displayedTagNumber,
            color: def.color,
            colorName: def.name,
            size: .compact
          )
        }
      }

      if isEditing {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            cancelEditing()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            saveEdits()
          }
          .disabled(!draft.hasChanges(comparedTo: animal))
        }
      } else {
        ToolbarItemGroup(placement: .topBarTrailing) {
          NavigationLink {
            AnimalTimelineView(animal: animal)
          } label: {
            Image(systemName: "clock.arrow.circlepath")
          }

          Button("Edit") {
            beginEditing()
          }
        }
      }
    }
    .onAppear {
      if animal.primaryTag == nil, !animal.tagNumber.isEmpty {
        _ = animal.ensurePrimaryTagRecord()
        saveContext()
      }
    }
  }

  @ViewBuilder
  private var editingContent: some View {
    statusSummarySection

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
      pastures: pastures,
      excludeAnimal: animal,
      showsStatusPicker: false
    )

    AnimalStatusEditorSection(
      status: $draft.status,
      statusReferenceID: $draft.statusReferenceID,
      saleDate: $draft.saleDate,
      salePriceText: $draft.salePriceText,
      reasonSold: $draft.reasonSold,
      deathDate: $draft.deathDate,
      causeOfDeath: $draft.causeOfDeath,
      availableStatusReferences: draftStatusReferences
    )
  }

  @ViewBuilder
  private var readOnlyContent: some View {
    statusSummarySection
    animalSummarySection
    statusQuickActionsSection
    statusDetailSection
    tagsSection
    recordManagementSection
  }

  @ViewBuilder
  private var statusSummarySection: some View {
    Section("Status") {
      LabeledContent("Current Status") {
        Label(displayedStatus.label, systemImage: displayedStatus.systemImage)
          .fontWeight(.semibold)
      }

      if let selectedStatusReference {
        LabeledContent("Status Reference") {
          Text(selectedStatusReference.name)
            .fontWeight(.medium)
        }
      }

      if animal.isArchived {
        LabeledContent("Record State") {
          Label("Archived", systemImage: "archivebox.fill")
            .foregroundStyle(.orange)
        }

        if let archivedAt = animal.archivedAt {
          LabeledContent("Archived On") {
            Text(archivedAt.formatted(date: .abbreviated, time: .omitted))
          }
        }
      }
    }
  }

  @ViewBuilder
  private var animalSummarySection: some View {
    Section("Details") {
      LabeledContent("Birth Date") {
        Text(animal.birthDate.formatted(date: .abbreviated, time: .omitted))
      }

      LabeledContent("Sex") {
        Text((animal.sex ?? .female).label)
      }

      LabeledContent("Pasture") {
        Text(animal.pasture?.name ?? "None")
      }
    }

    Section("Parents") {
      LabeledContent("Dam") {
        Text(animal.dam ?? "—")
      }

      LabeledContent("Sire") {
        Text(animal.sire ?? "—")
      }
    }

    Section("Identification") {
      if !animal.displayTagNumber.isEmpty {
        HStack {
          Text("Tag")
          Spacer()
          let def = tagColorLibrary.resolvedDefinition(for: animal)
          AnimalTagView(
            tagNumber: animal.displayTagNumber,
            color: def.color,
            colorName: def.name
          )
        }
      }

      LabeledContent("Name") {
        Text(animal.name.nilIfEmpty ?? "—")
      }
    }

    Section("Distinguishing Features") {
      if animal.distinguishingFeatures.isEmpty {
        Text("No distinguishing features")
          .foregroundStyle(.secondary)
      } else {
        ForEach(animal.distinguishingFeatures) { feature in
          Text(feature.description)
        }
      }
    }
  }

  @ViewBuilder
  private var statusQuickActionsSection: some View {
    Section("Quick Actions") {
      switch animal.status {
      case .active:
        Button {
          updateStatus(.sold)
        } label: {
          Label("Mark Sold", systemImage: AnimalStatus.sold.systemImage)
        }

        Button {
          updateStatus(.dead)
        } label: {
          Label("Mark Dead", systemImage: AnimalStatus.dead.systemImage)
        }

      case .sold:
        Button {
          updateStatus(.active)
        } label: {
          Label("Return to Active", systemImage: AnimalStatus.active.systemImage)
        }

        Button {
          updateStatus(.dead)
        } label: {
          Label("Correct to Dead", systemImage: AnimalStatus.dead.systemImage)
        }

      case .dead:
        Button {
          updateStatus(.active)
        } label: {
          Label("Correct to Active", systemImage: AnimalStatus.active.systemImage)
        }

        Button {
          updateStatus(.sold)
        } label: {
          Label("Correct to Sold", systemImage: AnimalStatus.sold.systemImage)
        }
      }
    }
  }

  @ViewBuilder
  private var statusDetailSection: some View {
    switch animal.status {
    case .active:
      EmptyView()

    case .sold:
      Section("Sale Details") {
        LabeledContent("Sale Date") {
          Text((animal.saleDate ?? .now).formatted(date: .abbreviated, time: .omitted))
        }

        LabeledContent("Sale Price") {
          Text(
            animal.salePrice?.formatted(
              .currency(code: Locale.current.currency?.identifier ?? "USD"))
              ?? "—"
          )
        }

        if let reasonSold = animal.reasonSold, !reasonSold.isEmpty {
          LabeledContent("Reason Sold") {
            Text(reasonSold)
              .multilineTextAlignment(.trailing)
          }
        }
      }

    case .dead:
      Section("Death Details") {
        LabeledContent("Death Date") {
          Text((animal.deathDate ?? .now).formatted(date: .abbreviated, time: .omitted))
        }

        if let causeOfDeath = animal.causeOfDeath, !causeOfDeath.isEmpty {
          LabeledContent("Cause of Death") {
            Text(causeOfDeath)
              .multilineTextAlignment(.trailing)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var tagsSection: some View {
    Section("Tags") {
      if animal.activeTags.isEmpty {
        Text("No active tags")
          .foregroundStyle(.secondary)
      } else {
        ForEach(animal.activeTags) { tag in
          tagRow(for: tag)
        }
      }

      Button("Add Tag") {
        showingAddTag = true
      }
    }
  }

  @ViewBuilder
  private var recordManagementSection: some View {
    Section {
      if animal.isArchived {
        Button {
          animal.restoreArchivedRecord()
          saveContext()
        } label: {
          Label("Restore Archived Record", systemImage: "arrow.uturn.backward.circle.fill")
        }
      } else {
        Button(role: .destructive) {
          showingArchiveConfirmation = true
        } label: {
          Label("Archive Record", systemImage: "archivebox")
        }
        .foregroundStyle(.orange)
      }
    } header: {
      Text("Record Management")
    } footer: {
      Text(
        "Archiving hides the record from normal herd views without changing the animal's herd status."
      )
    }

    Section {
      Button("Permanently Delete", role: .destructive) {
        showingHardDeleteConfirmation = true
      }
    } header: {
      Text("Danger Zone")
    } footer: {
      if hardDeleteOnSwipe {
        Text(
          "Swipe actions on the animal list permanently delete records while this setting is enabled."
        )
      } else {
        Text("Permanent delete removes the animal and all related records from the app.")
      }
    }
  }

  @ViewBuilder
  private func tagRow(for tag: AnimalTag) -> some View {
    HStack(spacing: 12) {
      tagBadge(for: tag)
      Spacer()
      if tag.isPrimary {
        Label("Primary", systemImage: "star.fill")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .contentShape(Rectangle())
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button("Retire", role: .destructive) {
        animal.retireTag(tag)
        saveContext()
      }
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      if !tag.isPrimary {
        Button("Set Primary") {
          animal.promoteTagToPrimary(tag)
          saveContext()
        }
        .tint(.blue)
      }
    }
  }

  private func tagBadge(for tag: AnimalTag) -> some View {
    let def = tagColorLibrary.definition(for: tag.colorID) ?? tagColorLibrary.defaultColor
    return AnimalTagView(
      tagNumber: tag.normalizedNumber,
      color: def.color,
      colorName: def.name,
      size: .compact
    )
  }

  private func beginEditing() {
    draft = AnimalEditorDraft(animal: animal)
    isEditing = true
  }

  private func cancelEditing() {
    draft = AnimalEditorDraft(animal: animal)
    isEditing = false
  }

  private func saveEdits() {
    do {
      try draft.apply(to: animal, in: context)
      try context.save()
      draft = AnimalEditorDraft(animal: animal)
      isEditing = false
    } catch {
      saveErrorMessage = error.localizedDescription
      showingSaveError = true
    }
  }

  private func updateStatus(_ newStatus: AnimalStatus) {
    let oldStatus = animal.status
    let oldStatusReferenceID = animal.statusReferenceID
    animal.applyStatus(newStatus)

    let record = StatusRecord(
      date: Date(),
      oldStatus: oldStatus,
      newStatus: newStatus,
      oldStatusReferenceID: oldStatusReferenceID,
      newStatusReferenceID: animal.statusReferenceID,
      animal: animal
    )
    context.insert(record)
    saveContext()
  }

  private func saveContext() {
    try? context.save()
  }
}

private struct AnimalTagEditView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

  @State private var number = ""
  @State private var colorID: UUID?
  @State private var isPrimary = false

  let onSave: (String, UUID?, Bool) -> Void

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

  var body: some View {
    NavigationStack {
      Form {
        Section("Tag Number") {
          TextField("Number", text: $number)
            .keyboardType(.numberPad)
            .font(.title2)
        }

        Section("Color") {
          LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tagColorLibrary.colors) { def in
              let isSelected = def.id == colorID

              Circle()
                .fill(def.color)
                .frame(height: 44)
                .overlay {
                  if isSelected {
                    Circle()
                      .strokeBorder(.primary, lineWidth: 3)
                  }
                }
                .onTapGesture {
                  colorID = def.id
                }
            }
          }
          .padding(.vertical, 4)

          Button("Clear Color") {
            colorID = nil
          }
          .foregroundStyle(.secondary)
        }

        Section {
          Toggle("Use as primary tag", isOn: $isPrimary)
        } footer: {
          Text(
            "Swipe right on an active tag in the animal detail screen to make it primary. Swipe left to retire it."
          )
        }
      }
      .navigationTitle("Add Tag")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(number.trimmingCharacters(in: .whitespacesAndNewlines), colorID, isPrimary)
          }
        }
      }
    }
  }
}
