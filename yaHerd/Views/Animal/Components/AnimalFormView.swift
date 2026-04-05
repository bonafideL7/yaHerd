//
// AnimalFormView.swift
//

import SwiftData
import SwiftUI

struct AnimalEditorDraft {
  var name: String = ""
  var tagNumber: String = ""
  var tagColorID: UUID?
  var sex: Sex = .unknown
  var birthDate: Date = .now
  var status: AnimalStatus = .active
  var pasture: Pasture?
  var sire: String = ""
  var dam: String = ""
  var distinguishingFeatures: [DistinguishingFeature] = []
  var saleDate: Date = .now
  var salePriceText: String = ""
  var reasonSold: String = ""
  var deathDate: Date = .now
  var causeOfDeath: String = ""
  var statusReferenceID: UUID?

  init() {}

  init(animal: Animal) {
    name = animal.name
    tagNumber = animal.displayTagNumber
    tagColorID = animal.displayTagColorID
    sex = animal.sex ?? .female
    birthDate = animal.birthDate
    status = animal.status
    pasture = animal.pasture
    sire = animal.sire ?? ""
    dam = animal.dam ?? ""
    distinguishingFeatures = animal.distinguishingFeatures
    saleDate = animal.saleDate ?? .now
    salePriceText =
      animal.salePrice.map {
        $0.formatted(.number.precision(.fractionLength(0...2)))
      } ?? ""
    reasonSold = animal.reasonSold ?? ""
    deathDate = animal.deathDate ?? .now
    causeOfDeath = animal.causeOfDeath ?? ""
    statusReferenceID = animal.statusReferenceID
  }

  var normalizedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var normalizedTagNumber: String {
    tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var normalizedSire: String? {
    sire.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  var normalizedDam: String? {
    dam.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  var normalizedReasonSold: String? {
    reasonSold.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  var normalizedCauseOfDeath: String? {
    causeOfDeath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  var cleanedDistinguishingFeatures: [DistinguishingFeature] {
    distinguishingFeatures
      .map {
        DistinguishingFeature(
          id: $0.id,
          description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines)
        )
      }
      .filter { !$0.description.isEmpty }
  }

  func parsedSalePrice() throws -> Double? {
    let trimmed = salePriceText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    guard let value = Double(trimmed) else {
      throw ValidationService.ValidationError("Sale price must be a valid number.")
    }

    return value
  }

  func validate() throws {
    try ValidationService.validateAnimal(birthDate: birthDate)
    _ = try parsedSalePrice()
  }

  func hasChanges(comparedTo animal: Animal) -> Bool {
    if normalizedName != animal.name { return true }
    if normalizedTagNumber != animal.displayTagNumber { return true }
    if tagColorID != animal.displayTagColorID { return true }
    if sex != (animal.sex ?? .female) { return true }
    if birthDate != animal.birthDate { return true }
    if pasture !== animal.pasture { return true }
    if normalizedSire != animal.sire { return true }
    if normalizedDam != animal.dam { return true }
    if cleanedDistinguishingFeatures != animal.distinguishingFeatures { return true }
    if status != animal.status { return true }
    if statusReferenceID != animal.statusReferenceID { return true }
    if saleDate != (animal.saleDate ?? .now) { return true }
    if normalizedReasonSold != animal.reasonSold { return true }
    if deathDate != (animal.deathDate ?? .now) { return true }
    if normalizedCauseOfDeath != animal.causeOfDeath { return true }

    let currentSalePriceText =
      animal.salePrice.map {
        $0.formatted(.number.precision(.fractionLength(0...2)))
      } ?? ""
    if salePriceText.trimmingCharacters(in: .whitespacesAndNewlines) != currentSalePriceText {
      return true
    }

    return false
  }

  func makeAnimal() throws -> Animal {
    try validate()

    let salePrice = try parsedSalePrice()

    return Animal(
      name: normalizedName,
      tagNumber: normalizedTagNumber,
      tagColorID: tagColorID,
      birthDate: birthDate,
      status: status,
      saleDate: status == .sold ? saleDate : nil,
      salePrice: status == .sold ? salePrice : nil,
      reasonSold: status == .sold ? normalizedReasonSold : nil,
      deathDate: status == .dead ? deathDate : nil,
      causeOfDeath: status == .dead ? normalizedCauseOfDeath : nil,
      statusReferenceID: statusReferenceID,
      sire: normalizedSire,
      dam: normalizedDam,
      pasture: pasture,
      sex: sex,
      distinguishingFeatures: cleanedDistinguishingFeatures
    )
  }

  func apply(to animal: Animal, in context: ModelContext) throws {
    try validate()

    let oldStatus = animal.status
    let oldStatusReferenceID = animal.statusReferenceID
    let salePrice = try parsedSalePrice()

    animal.name = normalizedName
    animal.sex = sex
    animal.birthDate = birthDate
    animal.sire = normalizedSire
    animal.dam = normalizedDam
    animal.distinguishingFeatures = cleanedDistinguishingFeatures

    if normalizedTagNumber.isEmpty, animal.tags.isEmpty {
      animal.tagNumber = ""
      animal.tagColorID = tagColorID
    } else {
      animal.updatePrimaryTag(number: normalizedTagNumber, colorID: tagColorID)
    }

    if animal.pasture !== pasture {
      AnimalMovementService.move(animal, to: pasture, in: context, save: false)
    }

    if animal.status != status {
      animal.applyStatus(status, effectiveDate: statusEffectiveDate)

      let record = StatusRecord(
        date: .now,
        oldStatus: oldStatus,
        newStatus: status,
        oldStatusReferenceID: oldStatusReferenceID,
        newStatusReferenceID: statusReferenceID,
        animal: animal
      )
      context.insert(record)
    }

    animal.status = status
    animal.statusReferenceID = statusReferenceID

    switch status {
    case .active:
      animal.saleDate = nil
      animal.salePrice = nil
      animal.reasonSold = nil
      animal.deathDate = nil
      animal.causeOfDeath = nil
    case .sold:
      animal.saleDate = saleDate
      animal.salePrice = salePrice
      animal.reasonSold = normalizedReasonSold
      animal.deathDate = nil
      animal.causeOfDeath = nil
    case .dead:
      animal.deathDate = deathDate
      animal.causeOfDeath = normalizedCauseOfDeath
      animal.saleDate = nil
      animal.salePrice = nil
      animal.reasonSold = nil
    }
  }

  private var statusEffectiveDate: Date {
    switch status {
    case .active:
      .now
    case .sold:
      saleDate
    case .dead:
      deathDate
    }
  }
}

enum ParentPickerType: Identifiable {
  case sire
  case dam

  var id: Int {
    switch self {
    case .sire: return 1
    case .dam: return 2
    }
  }
}

extension Sequence where Element == AnimalStatusReference {
  func matchingBaseStatus(_ status: AnimalStatus) -> [AnimalStatusReference] {
    filter { $0.baseStatus == status }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}

struct TagFieldRow: View {
  @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

  @Binding var tagNumber: String
  @Binding var tagColorID: UUID?

  @State private var showEditor = false

  private var selectedDef: TagColorDefinition? {
    tagColorLibrary.colors.first(where: { $0.id == tagColorID })
  }

  var body: some View {
    Button {
      showEditor = true
    } label: {
      HStack {
        Text("Tag")
        Spacer()

        if let def = selectedDef, !tagNumber.isEmpty {
          AnimalTagView(
            tagNumber: tagNumber,
            color: def.color,
            colorName: def.name
          )
        } else {
          Text("Not Set")
            .foregroundStyle(.secondary)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $showEditor) {
      TagEditorView(
        tagNumber: $tagNumber,
        tagColorID: $tagColorID
      )
      .presentationDetents([.medium, .large])
    }
  }
}

struct TagEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

  @Binding var tagNumber: String
  @Binding var tagColorID: UUID?

  @State private var tempNumber: String = ""
  @State private var tempColorID: UUID?

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

  var body: some View {
    NavigationStack {
      Form {
        Section("Tag Number") {
          TextField("Number", text: $tempNumber)
            .keyboardType(.numberPad)
            .font(.title2)
        }

        Section("Color") {
          LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tagColorLibrary.colors) { def in
              let isSelected = def.id == tempColorID

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
                  tempColorID = def.id
                }
            }
          }
          .padding(.vertical, 4)

          Button("Clear Color") {
            tempColorID = nil
          }
          .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Edit Tag")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            tagNumber = tempNumber
            tagColorID = tempColorID
            dismiss()
          }
        }
      }
    }
    .onAppear {
      tempNumber = tagNumber
      tempColorID = tagColorID
    }
  }
}

struct DistinguishingFeaturesSection: View {
  @Binding var features: [DistinguishingFeature]

  var body: some View {
    Section("Distinguishing Features") {
      if features.isEmpty {
        Text("No distinguishing features")
          .foregroundStyle(.secondary)
      }

      ForEach($features) { $feature in
        TextField("Feature", text: $feature.description)
      }
      .onDelete { offsets in
        features.remove(atOffsets: offsets)
      }

      Button("Add Feature") {
        features.append(DistinguishingFeature(description: ""))
      }
    }
  }
}

struct DateFieldRow: View {
  let title: String
  @Binding var date: Date

  @State private var isPresentingPicker = false

  private var formattedDate: String {
    date.formatted(date: .abbreviated, time: .omitted)
  }

  var body: some View {
    Button {
      isPresentingPicker = true
    } label: {
      LabeledContent(title) {
        Text(formattedDate)
          .foregroundStyle(.primary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $isPresentingPicker) {
      NavigationStack {
        Form {
          Section {
            DatePicker(
              title,
              selection: $date,
              displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
          } footer: {
            Text("Selected date: \(formattedDate)")
          }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
              isPresentingPicker = false
            }
          }
        }
      }
      .presentationDetents([.medium, .large])
    }
  }
}

struct AnimalStatusEditorSection: View {
  @Binding var status: AnimalStatus
  @Binding var statusReferenceID: UUID?
  @Binding var saleDate: Date
  @Binding var salePriceText: String
  @Binding var reasonSold: String
  @Binding var deathDate: Date
  @Binding var causeOfDeath: String

  let availableStatusReferences: [AnimalStatusReference]

  var body: some View {
    Group {
      if !availableStatusReferences.isEmpty || statusReferenceID != nil {
        Section {
          Picker("Referenced Status", selection: $statusReferenceID) {
            Text("None").tag(UUID?.none)

            ForEach(availableStatusReferences) { reference in
              Text(reference.name)
                .tag(UUID?.some(reference.id))
            }
          }
        } header: {
          Text("Status Reference")
        } footer: {
          Text(
            "Use a referenced status definition for user-defined herd statuses. The base herd status remains Active, Sold, or Dead."
          )
        }
      }

      switch status {
      case .active:
        EmptyView()

      case .sold:
        Section("Sale Details") {
          DateFieldRow(title: "Sale Date", date: $saleDate)
          TextField("Sale Price", text: $salePriceText)
            .keyboardType(.decimalPad)
          TextField("Reason Sold", text: $reasonSold, axis: .vertical)
            .lineLimit(2...4)
        }

      case .dead:
        Section("Death Details") {
          DateFieldRow(title: "Death Date", date: $deathDate)
          TextField("Cause of Death", text: $causeOfDeath, axis: .vertical)
            .lineLimit(2...4)
        }
      }
    }
  }
}

struct ParentFieldRow: View {
  let title: String
  @Binding var value: String
  let type: ParentPickerType
  @Binding var activePicker: ParentPickerType?

  var body: some View {
    Button {
      activePicker = type
    } label: {
      LabeledContent(title) {
        Text(value.isEmpty ? "Select" : value)
          .foregroundStyle(value.isEmpty ? Color.secondary : Color.primary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if !value.isEmpty {
        Button("Clear", role: .destructive) {
          value = ""
        }
      }
    }
  }
}

struct AnimalFormView: View {
  @Binding var name: String
  @Binding var tagNumber: String
  @Binding var tagColorID: UUID?
  @Binding var sex: Sex
  @Binding var birthDate: Date
  @Binding var status: AnimalStatus
  @Binding var pasture: Pasture?
  @Binding var sire: String
  @Binding var dam: String
  @Binding var distinguishingFeatures: [DistinguishingFeature]
  @Binding var activeParentPicker: ParentPickerType?

  let pastures: [Pasture]
  let showsStatusPicker: Bool

  var body: some View {
    Group {
      Section("Overview") {
        DateFieldRow(title: "Birth Date", date: $birthDate)

        Picker("Sex", selection: $sex) {
          ForEach(Sex.allCases, id: \.self) { sex in
            Text(sex.label).tag(sex)
          }
        }

        Picker("Pasture", selection: $pasture) {
          Text("None").tag(Pasture?.none)

          ForEach(pastures) { pasture in
            Text(pasture.name)
              .tag(Optional(pasture))
          }
        }

        if showsStatusPicker {
          Picker("Status", selection: $status) {
            ForEach(AnimalStatus.allCases, id: \.self) { status in
              Label(status.label, systemImage: status.systemImage)
                .tag(status)
            }
          }
        }
      }

      Section("Parents") {
        ParentFieldRow(
          title: "Dam",
          value: $dam,
          type: .dam,
          activePicker: $activeParentPicker
        )

        ParentFieldRow(
          title: "Sire",
          value: $sire,
          type: .sire,
          activePicker: $activeParentPicker
        )
      }

      Section("Identification") {
        TagFieldRow(
          tagNumber: $tagNumber,
          tagColorID: $tagColorID
        )

        TextField("Name", text: $name)
      }

      DistinguishingFeaturesSection(features: $distinguishingFeatures)
    }
  }
}

struct AnimalEditorSections: View {
  @Binding var draft: AnimalEditorDraft
  @Binding var activeParentPicker: ParentPickerType?

  let pastures: [Pasture]
  let statusReferences: [AnimalStatusReference]
  let showsStatusPicker: Bool

  private var availableStatusReferences: [AnimalStatusReference] {
    statusReferences.matchingBaseStatus(draft.status)
  }

  var body: some View {
    Group {
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
        showsStatusPicker: showsStatusPicker
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
  }
}

private struct AnimalParentPickerSheetModifier: ViewModifier {
  @Binding var activePicker: ParentPickerType?
  @Binding var sire: String
  @Binding var dam: String

  let excludeAnimal: Animal?

  func body(content: Content) -> some View {
    content.sheet(item: $activePicker) { picker in
      switch picker {
      case .sire:
        AnimalParentPickerView(
          title: "Select Sire",
          excludeAnimal: excludeAnimal,
          suggestedSexes: [.male]
        ) { picked in
          sire = picked.displayTagNumber
          activePicker = nil
        }

      case .dam:
        AnimalParentPickerView(
          title: "Select Dam",
          excludeAnimal: excludeAnimal,
          suggestedSexes: [.female]
        ) { picked in
          dam = picked.displayTagNumber
          activePicker = nil
        }
      }
    }
  }
}

extension View {
  func animalParentPickerSheet(
    activePicker: Binding<ParentPickerType?>,
    sire: Binding<String>,
    dam: Binding<String>,
    excludeAnimal: Animal?
  ) -> some View {
    modifier(
      AnimalParentPickerSheetModifier(
        activePicker: activePicker,
        sire: sire,
        dam: dam,
        excludeAnimal: excludeAnimal
      )
    )
  }
}

extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
