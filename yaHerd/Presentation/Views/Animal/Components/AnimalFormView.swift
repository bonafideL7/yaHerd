//
// AnimalFormView.swift
//

import SwiftUI

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

struct AnimalTagEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @State private var number: String
    @State private var colorID: UUID?
    @State private var isPrimary: Bool

    private let title: String
    private let saveButtonTitle: String
    private let showsPrimaryToggle: Bool
    private let onSave: (String, UUID?, Bool) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    init(
        initialNumber: String = "",
        initialColorID: UUID? = nil,
        initialIsPrimary: Bool = false,
        title: String = "Add Tag",
        saveButtonTitle: String = "Save",
        showsPrimaryToggle: Bool = false,
        onSave: @escaping (String, UUID?, Bool) -> Void
    ) {
        _number = State(initialValue: initialNumber)
        _colorID = State(initialValue: initialColorID)
        _isPrimary = State(initialValue: initialIsPrimary)
        self.title = title
        self.saveButtonTitle = saveButtonTitle
        self.showsPrimaryToggle = showsPrimaryToggle
        self.onSave = onSave
    }

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

                if showsPrimaryToggle {
                    Section {
                        Toggle("Use as primary tag", isOn: $isPrimary)
                    } footer: {
                        Text("Primary tags become the animal's display tag.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) {
                        onSave(number.trimmingCharacters(in: .whitespacesAndNewlines), colorID, isPrimary)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AnimalTagManagementActions {
    let onAdd: (String, UUID?, Bool) -> Void
    let onPromote: (UUID) -> Void
    let onRetire: (UUID) -> Void
}

struct AnimalTagManagementSection: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let detail: AnimalDetailSnapshot
    let actions: AnimalTagManagementActions
    let onAddTag: () -> Void

    var body: some View {
        Section {
            ForEach(detail.activeTags) { tag in
                activeTagRow(for: tag)
            }

            if !detail.inactiveTags.isEmpty {
                DisclosureGroup("Retired Tags (\(detail.inactiveTags.count))") {
                    ForEach(detail.inactiveTags) { tag in
                        inactiveTagRow(for: tag)
                    }
                }
            }

            Button(action: onAddTag) {
                Label("Add Tag", systemImage: "plus")
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Add secondary tags, promote an active tag to primary, or retire a tag from here.")
        }
    }

    private func activeTagRow(for tag: AnimalTagSnapshot) -> some View {
        HStack(spacing: 12) {
            tagBadge(for: tag)
            Spacer()
            if tag.isPrimary {
                Label("Primary", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !tag.isPrimary {
                Button {
                    actions.onPromote(tag.id)
                } label: {
                    Label("Make Primary", systemImage: "star")
                }
                .tint(.yellow)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                actions.onRetire(tag.id)
            } label: {
                Label("Retire", systemImage: "archivebox")
            }
        }
    }

    private func inactiveTagRow(for tag: AnimalTagSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            tagBadge(for: tag)
                .opacity(0.65)

            if let removedAt = tag.removedAt {
                Text("Retired \(removedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func tagBadge(for tag: AnimalTagSnapshot) -> some View {
        let def = tagColorLibrary.resolvedDefinition(tagColorID: tag.colorID)
        return AnimalTagView(
            tagNumber: tag.normalizedNumber,
            color: def.color,
            colorName: def.name,
            size: .compact
        )
    }
}

struct PendingAnimalTagManagementSection: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @Binding var tagNumber: String
    @Binding var tagColorID: UUID?
    @Binding var pendingTags: [AnimalTagSnapshot]

    let onAddTag: () -> Void

    var body: some View {
        Section {
            ForEach(pendingTags) { tag in
                HStack(spacing: 12) {
                    tagBadge(for: tag)
                    Spacer()
                    if tag.isPrimary {
                        Label("Primary", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if !tag.isPrimary {
                        Button {
                            makePrimary(tag.id)
                        } label: {
                            Label("Make Primary", systemImage: "star")
                        }
                        .tint(.yellow)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTag(tag.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Button(action: onAddTag) {
                Label("Add Tag", systemImage: "plus")
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Add secondary tags, promote an active tag to primary, or remove a pending tag from here.")
        }
    }

    private func makePrimary(_ tagID: UUID) {
        pendingTags = pendingTags.map { tag in
            AnimalTagSnapshot(
                id: tag.id,
                number: tag.number,
                colorID: tag.colorID,
                isPrimary: tag.id == tagID,
                isActive: tag.isActive,
                assignedAt: tag.assignedAt,
                removedAt: tag.removedAt
            )
        }

        syncPrimaryTag()
    }

    private func deleteTag(_ tagID: UUID) {
        pendingTags.removeAll { $0.id == tagID }

        if !pendingTags.contains(where: { $0.isPrimary }), let firstID = pendingTags.first?.id {
            makePrimary(firstID)
        } else {
            syncPrimaryTag()
        }
    }

    private func syncPrimaryTag() {
        if let primary = pendingTags.first(where: { $0.isPrimary }) {
            tagNumber = primary.normalizedNumber
            tagColorID = primary.colorID
        } else {
            tagNumber = ""
            tagColorID = nil
        }
    }

    private func tagBadge(for tag: AnimalTagSnapshot) -> some View {
        let def = tagColorLibrary.resolvedDefinition(tagColorID: tag.colorID)
        return AnimalTagView(
            tagNumber: tag.normalizedNumber,
            color: def.color,
            colorName: def.name,
            size: .compact
        )
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

    let availableStatusReferences: [AnimalStatusReferenceOption]

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
    @Binding var pastureID: UUID?
    @Binding var sire: String
    @Binding var dam: String
    @Binding var distinguishingFeatures: [DistinguishingFeature]
    @Binding var activeParentPicker: ParentPickerType?

    let pastures: [PastureOption]
    let showsStatusPicker: Bool
    let tagDetail: AnimalDetailSnapshot?
    let tagActions: AnimalTagManagementActions?
    let pendingTags: Binding<[AnimalTagSnapshot]>?
    let onAddExistingTag: (() -> Void)?
    let onAddPendingTag: (() -> Void)?

    var body: some View {
        Group {
            Section("Overview") {
                DateFieldRow(title: "Birth Date", date: $birthDate)

                Picker("Sex", selection: $sex) {
                    ForEach(Sex.allCases, id: \.self) { sex in
                        Text(sex.label).tag(sex)
                    }
                }

                Picker("Pasture", selection: $pastureID) {
                    Text("None").tag(UUID?.none)

                    ForEach(pastures) { pasture in
                        Text(pasture.name)
                            .tag(UUID?.some(pasture.id))
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
                
                TextField("Name", text: $name)
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

            if let tagDetail, let tagActions, let onAddExistingTag {
                AnimalTagManagementSection(
                    detail: tagDetail,
                    actions: tagActions,
                    onAddTag: onAddExistingTag
                )
            } else if let pendingTags, let onAddPendingTag {
                PendingAnimalTagManagementSection(
                    tagNumber: $tagNumber,
                    tagColorID: $tagColorID,
                    pendingTags: pendingTags,
                    onAddTag: onAddPendingTag
                )
            }

            DistinguishingFeaturesSection(features: $distinguishingFeatures)
        }
    }
}

struct AnimalEditorSections: View {
    @Binding var draft: AnimalEditorDraft
    @Binding var activeParentPicker: ParentPickerType?

    let pastures: [PastureOption]
    let statusReferences: [AnimalStatusReferenceOption]
    let showsStatusPicker: Bool
    let tagDetail: AnimalDetailSnapshot?
    let tagActions: AnimalTagManagementActions?
    let pendingTags: Binding<[AnimalTagSnapshot]>?
    let onAddExistingTag: (() -> Void)?
    let onAddPendingTag: (() -> Void)?

    private var availableStatusReferences: [AnimalStatusReferenceOption] {
        statusReferences
            .filter { $0.baseStatus == draft.status }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                pastureID: $draft.pastureID,
                sire: $draft.sire,
                dam: $draft.dam,
                distinguishingFeatures: $draft.distinguishingFeatures,
                activeParentPicker: $activeParentPicker,
                pastures: pastures,
                showsStatusPicker: showsStatusPicker,
                tagDetail: tagDetail,
                tagActions: tagActions,
                pendingTags: pendingTags,
                onAddExistingTag: onAddExistingTag,
                onAddPendingTag: onAddPendingTag
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

    let excludeAnimalID: UUID?

    func body(content: Content) -> some View {
        content.sheet(item: $activePicker) { picker in
            switch picker {
            case .sire:
                AnimalParentPickerView(
                    title: "Select Sire",
                    excludeAnimalID: excludeAnimalID,
                    suggestedSexes: [.male]
                ) { picked in
                    sire = picked.displayTagNumber
                    activePicker = nil
                }

            case .dam:
                AnimalParentPickerView(
                    title: "Select Dam",
                    excludeAnimalID: excludeAnimalID,
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
        excludeAnimalID: UUID?
    ) -> some View {
        modifier(
            AnimalParentPickerSheetModifier(
                activePicker: activePicker,
                sire: sire,
                dam: dam,
                excludeAnimalID: excludeAnimalID
            )
        )
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
