//
//  AnimalDetailView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI
import SwiftData

struct AnimalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @AppStorage("allowHardDelete") private var hardDeleteOnSwipe = false
    @State private var activeParentPicker: ParentPickerType?
    @State private var showingAddTag = false
    @State private var showingArchiveConfirmation = false
    @State private var showingHardDeleteConfirmation = false
    var animal: Animal

    @Query(sort: \Pasture.name) private var pastures: [Pasture]
    @Query(sort: \AnimalStatusReference.name) private var statusReferences: [AnimalStatusReference]

    private var nameBinding: Binding<String> {
        Binding(
            get: { animal.name },
            set: { newValue in
                animal.name = newValue
                saveContext()
            }
        )
    }

    private var tagNumberBinding: Binding<String> {
        Binding(
            get: { animal.displayTagNumber },
            set: { newValue in
                animal.updatePrimaryTag(number: newValue, colorID: animal.displayTagColorID)
                saveContext()
            }
        )
    }

    private var tagColorIDBinding: Binding<UUID?> {
        Binding(
            get: { animal.displayTagColorID },
            set: { newValue in
                animal.updatePrimaryTag(number: animal.displayTagNumber, colorID: newValue)
                saveContext()
            }
        )
    }

    private var sexBinding: Binding<Sex> {
        Binding(
            get: { animal.sex ?? .female },
            set: { newValue in
                animal.sex = newValue
                saveContext()
            }
        )
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { animal.birthDate },
            set: { newValue in
                animal.birthDate = newValue
                saveContext()
            }
        )
    }

    private var statusBinding: Binding<AnimalStatus> {
        Binding(
            get: { animal.status },
            set: { newValue in
                guard animal.status != newValue else { return }
                updateStatus(newValue)
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
                saveContext()
            }
        )
    }

    private var saleDateBinding: Binding<Date> {
        Binding(
            get: { animal.saleDate ?? .now },
            set: { newValue in
                animal.saleDate = newValue
                saveContext()
            }
        )
    }

    private var salePriceTextBinding: Binding<String> {
        Binding(
            get: {
                guard let salePrice = animal.salePrice else { return "" }
                return salePrice.formatted(.number.precision(.fractionLength(0...2)))
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                animal.salePrice = Double(trimmed)
                saveContext()
            }
        )
    }

    private var reasonSoldBinding: Binding<String> {
        Binding(
            get: { animal.reasonSold ?? "" },
            set: { newValue in
                animal.reasonSold = newValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                saveContext()
            }
        )
    }

    private var deathDateBinding: Binding<Date> {
        Binding(
            get: { animal.deathDate ?? .now },
            set: { newValue in
                animal.deathDate = newValue
                saveContext()
            }
        )
    }

    private var causeOfDeathBinding: Binding<String> {
        Binding(
            get: { animal.causeOfDeath ?? "" },
            set: { newValue in
                animal.causeOfDeath = newValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                saveContext()
            }
        )
    }

    private var availableStatusReferences: [AnimalStatusReference] {
        statusReferences
            .filter { $0.baseStatus == animal.status }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var statusReferenceBinding: Binding<UUID?> {
        Binding(
            get: { animal.statusReferenceID },
            set: { newValue in
                animal.statusReferenceID = newValue
                saveContext()
            }
        )
    }

    private var selectedStatusReference: AnimalStatusReference? {
        guard let statusReferenceID = animal.statusReferenceID else { return nil }
        return statusReferences.first(where: { $0.id == statusReferenceID })
    }

    var body: some View {
        Form {
            statusSummarySection

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
                excludeAnimal: animal,
                showsStatusPicker: false
            )

            statusQuickActionsSection
            statusDetailSection
            tagsSection
            recordManagementSection
        }
        .sheet(item: $activeParentPicker) { picker in
            switch picker {
            case .sire:
                AnimalParentPickerView(
                    title: "Select Sire",
                    excludeAnimal: animal,
                    suggestedSexes: [.male]
                ) { picked in
                    animal.sire = picked.displayTagNumber
                    saveContext()
                    activeParentPicker = nil
                }

            case .dam:
                AnimalParentPickerView(
                    title: "Select Dam",
                    excludeAnimal: animal,
                    suggestedSexes: [.female]
                ) { picked in
                    animal.dam = picked.displayTagNumber
                    saveContext()
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
        .confirmationDialog("Archive this record?", isPresented: $showingArchiveConfirmation, titleVisibility: .visible) {
            Button("Archive Record", role: .destructive) {
                animal.archive()
                saveContext()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived records are hidden from normal herd views but can be restored later.")
        }
        .confirmationDialog("Permanently delete this animal?", isPresented: $showingHardDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
                context.delete(animal)
                saveContext()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the animal and all related records from the app.")
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
                saveContext()
            }
        }
    }

    @ViewBuilder
    private var statusSummarySection: some View {
        Section("Status") {
            LabeledContent("Current Status") {
                Label(animal.status.label, systemImage: animal.status.systemImage)
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
        if !availableStatusReferences.isEmpty || animal.statusReferenceID != nil {
            Section {
                Picker("Referenced Status", selection: statusReferenceBinding) {
                    Text("None").tag(UUID?.none)
                    
                    ForEach(availableStatusReferences) { reference in
                        Text(reference.name)
                            .tag(UUID?.some(reference.id))
                    }
                }
            } header: {
                Text("Status Reference")
            } footer: {
                Text("Use a referenced status definition for user-defined herd statuses. The base herd status remains Active, Sold, or Dead.")
            }
        }

        switch animal.status {
        case .active:
            EmptyView()

        case .sold:
            Section("Sale Details") {
                DatePicker("Sale Date", selection: saleDateBinding, displayedComponents: .date)
                TextField("Sale Price", text: salePriceTextBinding)
                    .keyboardType(.decimalPad)
                TextField("Reason Sold", text: reasonSoldBinding, axis: .vertical)
                    .lineLimit(2...4)
            }

        case .dead:
            Section("Death Details") {
                DatePicker("Death Date", selection: deathDateBinding, displayedComponents: .date)
                TextField("Cause of Death", text: causeOfDeathBinding, axis: .vertical)
                    .lineLimit(2...4)
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
            Text("Archiving hides the record from normal herd views without changing the animal's herd status.")
        }

        Section {
            Button("Permanently Delete", role: .destructive) {
                showingHardDeleteConfirmation = true
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            if hardDeleteOnSwipe {
                Text("Swipe actions on the animal list permanently delete records while this setting is enabled.")
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

    private func updatePasture(to newPasture: Pasture?) {
        AnimalMovementService.move(animal, to: newPasture, in: context)
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
