//
//  AnimalEditorSections.swift
//

import SwiftUI

struct AnimalFormView: View {
    @Binding var name: String
    @Binding var tagNumber: String
    @Binding var tagColorID: UUID?
    @Binding var sex: Sex
    @Binding var birthDate: Date
    @Binding var status: AnimalStatus
    @Binding var pastureID: UUID?
    @Binding var sireID: UUID?
    @Binding var sire: String
    @Binding var damID: UUID?
    @Binding var dam: String
    @Binding var distinguishingFeatures: [DistinguishingFeature]
    @Binding var activeParentPicker: ParentPickerType?

    @State private var isShowingNameField = false
    @FocusState private var isNameFieldFocused: Bool
    @State private var isParentsExpanded = false
    
    let pastures: [PastureOption]
    let tagDetail: AnimalDetailSnapshot?
    let tagActions: AnimalTagManagementActions?
    let pendingTags: Binding<[AnimalTagSnapshot]>?
    let onAddExistingTag: (() -> Void)?
    let onEditExistingTag: ((AnimalTagSnapshot) -> Void)?
    let onAddPendingTag: (() -> Void)?
    let onEditPendingTag: ((AnimalTagSnapshot) -> Void)?
    let draftTags: Binding<[AnimalTagSnapshot]>?
    let draftTagActions: AnimalTagManagementActions?
    let onAddDraftTag: (() -> Void)?
    let onEditDraftTag: ((AnimalTagSnapshot) -> Void)?
    
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var shouldShowNameField: Bool {
        isShowingNameField || isNameFieldFocused || !trimmedName.isEmpty
    }
    
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
                
                
            }
            
            if let tagDetail, let tagActions, let onAddExistingTag, let onEditExistingTag {
                AnimalTagManagementSection(
                    detail: tagDetail,
                    actions: AnimalTagManagementActions(
                        onEdit: onEditExistingTag,
                        onPromote: tagActions.onPromote,
                        onRetire: tagActions.onRetire
                    ),
                    onAddTag: onAddExistingTag
                )
            } else if let draftTags, let draftTagActions, let onAddDraftTag, let onEditDraftTag {
                DraftAnimalTagManagementSection(
                    draftTags: draftTags,
                    actions: AnimalTagManagementActions(
                        onEdit: onEditDraftTag,
                        onPromote: draftTagActions.onPromote,
                        onRetire: draftTagActions.onRetire
                    ),
                    onAddTag: onAddDraftTag
                )
            } else if let pendingTags, let onAddPendingTag, let onEditPendingTag {
                PendingAnimalTagManagementSection(
                    tagNumber: $tagNumber,
                    tagColorID: $tagColorID,
                    pendingTags: pendingTags,
                    onAddTag: onAddPendingTag,
                    onEditTag: onEditPendingTag
                )
            }
            
            Section("Name") {
                if shouldShowNameField {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($isNameFieldFocused)
                        .onAppear {
                            if isShowingNameField && trimmedName.isEmpty {
                                DispatchQueue.main.async {
                                    isNameFieldFocused = true
                                }
                            }
                        }
                        .onChange(of: isNameFieldFocused) { _, isFocused in
                            if !isFocused && trimmedName.isEmpty {
                                isShowingNameField = false
                            }
                        }
                } else {
                    Button {
                        isShowingNameField = true
                    } label: {
                        HStack {
                            Text("Add Name")
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }

            DistinguishingFeaturesSection(features: $distinguishingFeatures)
            
            Section {
                DisclosureGroup("Parents", isExpanded: $isParentsExpanded) {
                    ParentFieldRow(
                        title: "Dam",
                        value: $dam,
                        onClear: {
                            dam = ""
                            damID = nil
                        },
                        type: .dam,
                        activePicker: $activeParentPicker
                    )
                    
                    ParentFieldRow(
                        title: "Sire",
                        value: $sire,
                        onClear: {
                            sire = ""
                            sireID = nil
                        },
                        type: .sire,
                        activePicker: $activeParentPicker
                    )
                }
            } footer: {
                if !dam.isEmpty || !sire.isEmpty {
                    Text([
                        dam.isEmpty ? nil : "Dam: \(dam)",
                        sire.isEmpty ? nil : "Sire: \(sire)"
                    ]
                        .compactMap { $0 }
                        .joined(separator: " • "))
                }
            }
        }
    }
}

struct AnimalEditorSections: View {
    @Binding var draft: AnimalEditorDraft
    @Binding var activeParentPicker: ParentPickerType?
    
    let pastures: [PastureOption]
    let statusReferences: [AnimalStatusReferenceOption]
    let tagDetail: AnimalDetailSnapshot?
    let tagActions: AnimalTagManagementActions?
    let pendingTags: Binding<[AnimalTagSnapshot]>?
    let onAddExistingTag: (() -> Void)?
    let onEditExistingTag: ((AnimalTagSnapshot) -> Void)?
    let onAddPendingTag: (() -> Void)?
    let onEditPendingTag: ((AnimalTagSnapshot) -> Void)?
    let draftTags: Binding<[AnimalTagSnapshot]>?
    let draftTagActions: AnimalTagManagementActions?
    let onAddDraftTag: (() -> Void)?
    let onEditDraftTag: ((AnimalTagSnapshot) -> Void)?
    let scrollTarget: AnimalEditorScrollTarget?
    
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
                sireID: $draft.sireID,
                sire: $draft.sire,
                damID: $draft.damID,
                dam: $draft.dam,
                distinguishingFeatures: $draft.distinguishingFeatures,
                activeParentPicker: $activeParentPicker,
                pastures: pastures,
                tagDetail: tagDetail,
                tagActions: tagActions,
                pendingTags: pendingTags,
                onAddExistingTag: onAddExistingTag,
                onEditExistingTag: onEditExistingTag,
                onAddPendingTag: onAddPendingTag,
                onEditPendingTag: onEditPendingTag,
                draftTags: draftTags,
                draftTagActions: draftTagActions,
                onAddDraftTag: onAddDraftTag,
                onEditDraftTag: onEditDraftTag
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
            .id(scrollTarget)
        }
    }
}

private struct AnimalParentPickerSheetModifier: ViewModifier {
    @Binding var activePicker: ParentPickerType?
    @Binding var sireID: UUID?
    @Binding var sire: String
    @Binding var damID: UUID?
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
                    sireID = picked.id
                    sire = picked.displayTagNumber
                    activePicker = nil
                }
                
            case .dam:
                AnimalParentPickerView(
                    title: "Select Dam",
                    excludeAnimalID: excludeAnimalID,
                    suggestedSexes: [.female]
                ) { picked in
                    damID = picked.id
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
        sireID: Binding<UUID?>,
        sire: Binding<String>,
        damID: Binding<UUID?>,
        dam: Binding<String>,
        excludeAnimalID: UUID?
    ) -> some View {
        modifier(
            AnimalParentPickerSheetModifier(
                activePicker: activePicker,
                sireID: sireID,
                sire: sire,
                damID: damID,
                dam: dam,
                excludeAnimalID: excludeAnimalID
            )
        )
    }
}
