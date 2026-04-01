//
//  AnimalDetailView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI
import SwiftData

struct AnimalDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @AppStorage("allowHardDelete") private var allowHardDelete = false
    @State private var activeParentPicker: ParentPickerType?
    @State private var showingAddTag = false
    @State private var errorMessage: String?
    @State private var showingError = false
    var animal: Animal

    @Query(sort: \Pasture.name) private var pastures: [Pasture]

    private var nameBinding: Binding<String> {
        Binding(
            get: { animal.name },
            set: { newValue in
                animal.name = newValue
                try? context.save()
            }
        )
    }

    private var tagNumberBinding: Binding<String> {
        Binding(
            get: { animal.displayTagNumber },
            set: { newValue in
                do {
                    try ValidationService.validateAnimalTag(
                        number: newValue,
                        colorID: animal.displayTagColorID,
                        animal: animal,
                        context: context,
                        existingTag: animal.primaryTag
                    )
                    animal.updatePrimaryTag(number: newValue, colorID: animal.displayTagColorID)
                    try context.save()
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        )
    }

    private var tagColorIDBinding: Binding<UUID?> {
        Binding(
            get: { animal.displayTagColorID },
            set: { newValue in
                do {
                    try ValidationService.validateAnimalTag(
                        number: animal.displayTagNumber,
                        colorID: newValue,
                        animal: animal,
                        context: context,
                        existingTag: animal.primaryTag
                    )
                    animal.updatePrimaryTag(number: animal.displayTagNumber, colorID: newValue)
                    try context.save()
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        )
    }

    private var sexBinding: Binding<Sex> {
        Binding(
            get: { animal.sex ?? .female },
            set: { newValue in
                animal.sex = newValue
                try? context.save()
            }
        )
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { animal.birthDate },
            set: { newValue in
                animal.birthDate = newValue
                try? context.save()
            }
        )
    }

    private var statusBinding: Binding<AnimalStatus> {
        Binding(
            get: { animal.status },
            set: { newValue in
                guard animal.status != newValue else { return }
                let oldStatus = animal.status
                animal.status = newValue

                let record = StatusRecord(
                    date: Date(),
                    oldStatus: oldStatus,
                    newStatus: newValue,
                    animal: animal
                )
                context.insert(record)
                try? context.save()
            }
        )
    }

    private var pastureBinding: Binding<Pasture?> {
        Binding(
            get: { animal.pasture },
            set: { newValue in
                updatePasture(to: newValue)
            }
        )
    }

    private var sireBinding: Binding<String> {
        Binding(
            get: { animal.sire ?? "" },
            set: { animal.sire = $0.isEmpty ? nil : $0 }
        )
    }

    private var damBinding: Binding<String> {
        Binding(
            get: { animal.dam ?? "" },
            set: { animal.dam = $0.isEmpty ? nil : $0 }
        )
    }

    private var distinguishingFeaturesBinding: Binding<[DistinguishingFeature]> {
        Binding(
            get: { animal.distinguishingFeatures },
            set: { newValue in
                animal.distinguishingFeatures = newValue
                    .map { DistinguishingFeature(id: $0.id, description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .filter { !$0.description.isEmpty }
                try? context.save()
            }
        )
    }

    var body: some View {
        Form {
            AnimalFormView(
                name: nameBinding,
                tagNumber: tagNumberBinding,
                tagColorID: tagColorIDBinding,
                sex: sexBinding,
                birthDate: birthDateBinding,
                status: statusBinding,
                pasture: pastureBinding,
                sire: sireBinding,
                dam: damBinding,
                distinguishingFeatures: distinguishingFeaturesBinding,
                activeParentPicker: $activeParentPicker,
                pastures: pastures,
                excludeAnimal: animal
            )

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

            Section("Status Actions") {
                if animal.status != .sold {
                    Button("Mark as Sold") {
                        updateStatus(.sold)
                    }
                }

                if animal.status != .deceased {
                    Button("Mark as Deceased") {
                        updateStatus(.deceased)
                    }
                }

                if animal.status != .alive {
                    Button("Restore to Alive") {
                        updateStatus(.alive)
                    }
                    .foregroundStyle(.blue)
                }
            }

            Section("Delete Animal") {
                Button("Archive (Soft Delete)") {
                    updateStatus(.deceased)
                }
                .foregroundStyle(.orange)

                if allowHardDelete {
                    Button("Permanently Delete", role: .destructive) {
                        context.delete(animal)
                        try? context.save()
                    }
                }
            }
        }.sheet(item: $activeParentPicker) { picker in
            switch picker {

            case .sire:
                AnimalParentPickerView(
                    title: "Select Sire",
                    excludeAnimal: animal,
                    suggestedSexes: [.male]
                ) { picked in
                    animal.sire = picked.displayTagNumber
                    try? context.save()
                    activeParentPicker = nil
                }

            case .dam:
                AnimalParentPickerView(
                    title: "Select Dam",
                    excludeAnimal: animal,
                    suggestedSexes: [.female]
                ) { picked in
                    animal.dam = picked.displayTagNumber
                    try? context.save()
                    activeParentPicker = nil
                }
            }
        }
        .sheet(isPresented: $showingAddTag) {
            AnimalTagEditView { number, colorID, isPrimary in
                do {
                    try ValidationService.validateAnimalTag(
                        number: number,
                        colorID: colorID,
                        animal: animal,
                        context: context
                    )
                    _ = animal.addTag(number: number, colorID: colorID, isPrimary: isPrimary)
                    try context.save()
                    showingAddTag = false
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Validation Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .navigationTitle("Animal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                let def = tagColorLibrary.resolvedDefinition(for: animal)
                AnimalTagView(
                    tagNumber: animal.displayTagNumber,
                    color: def.color,
                    colorName: def.name,
                    size: .compact
                )
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AnimalTimelineView(animal: animal)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .onAppear {
            if animal.primaryTag == nil, !animal.tagNumber.isEmpty {
                _ = animal.ensurePrimaryTagRecord()
                try? context.save()
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
                try? context.save()
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !tag.isPrimary {
                Button("Set Primary") {
                    animal.promoteTagToPrimary(tag)
                    try? context.save()
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

    private func updatePasture(to newPasture: Pasture?) {
        AnimalMovementService.move(animal, to: newPasture, in: context)
    }

    private func updateStatus(_ newStatus: AnimalStatus) {
        let oldStatus = animal.status
        animal.status = newStatus

        let record = StatusRecord(
            date: Date(),
            oldStatus: oldStatus,
            newStatus: newStatus,
            animal: animal
        )
        context.insert(record)

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
                    Text("Swipe right on an active tag in the animal detail screen to make it primary. Swipe left to retire it.")
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
