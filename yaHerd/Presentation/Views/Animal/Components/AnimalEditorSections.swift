//
//  AnimalEditorSections.swift
//

import SwiftUI

struct AnimalEditorSections: View {
    @Binding var draft: AnimalEditorDraft
    @Binding var activeParentPicker: ParentPickerType?

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
    let scrollTarget: AnimalEditorScrollTarget?

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
                editorContext: editorContext,
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
                saleDate: $draft.saleDate,
                salePriceText: $draft.salePriceText,
                reasonSold: $draft.reasonSold,
                deathDate: $draft.deathDate,
                causeOfDeath: $draft.causeOfDeath
            )
            .id(scrollTarget)
        }
    }
}
