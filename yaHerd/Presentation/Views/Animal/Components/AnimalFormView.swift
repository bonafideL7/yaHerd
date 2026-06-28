//
//  AnimalFormView.swift
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

    let editorContext: AnimalEditorContext
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

    private var parentSummary: String {
        [
            dam.isEmpty ? nil : "Dam: \(dam)",
            sire.isEmpty ? nil : "Sire: \(sire)"
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    var body: some View {
        Group {
            Section("Overview") {
                DateFieldRow(
                    title: "Birth Date",
                    date: $birthDate,
                    quickSelections: editorContext.birthDateQuickSelections
                )

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
                if !parentSummary.isEmpty, let helperText = editorContext.offspringMetadata?.inferredSireHelperText {
                    Text(parentSummary + "\n\n" + helperText)
                } else if !parentSummary.isEmpty {
                    Text(parentSummary)
                } else if let helperText = editorContext.offspringMetadata?.inferredSireHelperText {
                    Text(helperText)
                }
            }
            .onAppear {
                if editorContext.offspringMetadata != nil, (!dam.isEmpty || !sire.isEmpty) {
                    isParentsExpanded = true
                }
            }
        }
    }
}
