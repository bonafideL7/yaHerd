//
//  AnimalDetailView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI

struct AnimalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @AppStorage("allowHardDelete") private var hardDeleteOnSwipe = false

    @State private var viewModel = AnimalDetailViewModel()
    @State private var activeParentPicker: ParentPickerType?
    @State private var showingError = false
    @State private var showingAddTag = false
    @State private var editingTag: AnimalTagSnapshot?
    @State private var isLineageExpanded = false
    
    let animalID: UUID

    init(animalID: UUID) {
        self.animalID = animalID
    }

    private var repository: any AnimalRepository {
        dependencies.animalRepository
    }

    private var displayedTagNumber: String {
        if viewModel.isEditing {
            return viewModel.form.draft.normalizedTagNumber
        }
        return viewModel.detail?.displayTagNumber ?? ""
    }

    private var displayedTagColorID: UUID? {
        if viewModel.isEditing {
            return viewModel.form.draft.tagColorID
        }
        return viewModel.detail?.displayTagColorID
    }

    var body: some View {
        Group {
            if let detail = viewModel.detail {
                ScrollViewReader { proxy in
                    Form {
                        if viewModel.isEditing {
                            editingContent
                        } else {
                            readOnlyContent(detail)
                        }
                    }
                    .onAppear {
                        scrollFormIfNeeded(using: proxy)
                    }
                    .onChange(of: viewModel.isEditing) { _, _ in
                        scrollFormIfNeeded(using: proxy)
                    }
                    .onChange(of: viewModel.pendingScrollTarget) { _, _ in
                        scrollFormIfNeeded(using: proxy)
                    }
                }
            } else {
                ContentUnavailableView("Animal Not Found", systemImage: "pawprint")
            }
        }
        .animalParentPickerSheet(
            activePicker: $activeParentPicker,
            sireID: Binding(
                get: { viewModel.form.draft.sireID },
                set: { viewModel.form.draft.sireID = $0 }
            ),
            sire: Binding(
                get: { viewModel.form.draft.sire },
                set: { viewModel.form.draft.sire = $0 }
            ),
            damID: Binding(
                get: { viewModel.form.draft.damID },
                set: { viewModel.form.draft.damID = $0 }
            ),
            dam: Binding(
                get: { viewModel.form.draft.dam },
                set: { viewModel.form.draft.dam = $0 }
            ),
            excludeAnimalID: animalID
        )
        .sheet(isPresented: $showingAddTag) {
            AnimalTagEditView(
                title: "Add Tag",
                saveButtonTitle: "Save",
                showsPrimaryToggle: true
            ) { number, colorID, isPrimary in
                viewModel.addDraftTag(number: number, colorID: colorID, isPrimary: isPrimary)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingTag) { tag in
            AnimalTagEditView(
                initialNumber: tag.normalizedNumber,
                initialColorID: tag.colorID,
                initialIsPrimary: tag.isPrimary,
                title: "Edit Tag",
                saveButtonTitle: "Save",
                showsPrimaryToggle: tag.isActive
            ) { number, colorID, isPrimary in
                viewModel.updateDraftTag(
                    tagID: tag.id,
                    number: number,
                    colorID: colorID,
                    isPrimary: tag.isActive ? isPrimary : false
                )
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Can’t Save", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .navigationTitle("Animal")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isEditing)
        .toolbar {
            if !displayedTagNumber.isEmpty {
                ToolbarItem(placement: .principal) {
                    let def = tagColorLibrary.resolvedDefinition(tagColorID: displayedTagColorID)
                    AnimalTagView(
                        tagNumber: displayedTagNumber,
                        color: def.color,
                        colorName: def.name,
                        size: .compact
                    )
                }
            }

            if viewModel.isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelEditing()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.save(animalID: animalID, using: repository)
                    }
                    .disabled(!canSaveChanges)
                }
            } else if viewModel.detail != nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        AnimalTimelineContainerView(animalID: animalID)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }

                    Button("Edit") {
                        viewModel.beginEditing()
                    }
                }
            }
        }
        .task {
            if !viewModel.hasLoaded {
                viewModel.load(animalID: animalID, using: repository)
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showingError = newValue != nil
        }
        .onChange(of: viewModel.didDelete) { _, didDelete in
            if didDelete {
                dismiss()
            }
        }
    }

    private var canSaveChanges: Bool {
        guard let detail = viewModel.detail else { return false }
        let draftChanged = viewModel.form.draft.hasChanges(comparedTo: detail)
        let tagChanged = viewModel.draftTags != (detail.activeTags + detail.inactiveTags)
        return draftChanged || tagChanged
    }

    private func scrollFormIfNeeded(using proxy: ScrollViewProxy) {
        guard viewModel.isEditing, let target = viewModel.pendingScrollTarget else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private var editingContent: some View {
        AnimalEditorSections(
            draft: Binding(
                get: { viewModel.form.draft },
                set: { viewModel.form.draft = $0 }
            ),
            activeParentPicker: $activeParentPicker,
            pastures: viewModel.form.pastureOptions,
            statusReferences: viewModel.form.statusReferenceOptions,
            tagDetail: nil,
            tagActions: nil,
            pendingTags: nil,
            onAddExistingTag: { showingAddTag = true },
            onEditExistingTag: { editingTag = $0 },
            onAddPendingTag: nil,
            onEditPendingTag: nil,
            draftTags: Binding(
                get: { viewModel.draftTags },
                set: { viewModel.draftTags = $0 }
            ),
            draftTagActions: AnimalTagManagementActions(
                onEdit: { tag in
                    editingTag = tag
                },
                onPromote: { tagID in
                    viewModel.promoteDraftTag(tagID: tagID)
                },
                onRetire: { tagID in
                    viewModel.retireDraftTag(tagID: tagID)
                }
            ),
            onAddDraftTag: { showingAddTag = true },
            onEditDraftTag: { editingTag = $0 },
            scrollTarget: .status
        )
    }

    @ViewBuilder
    private func readOnlyContent(_ detail: AnimalDetailSnapshot) -> some View {
        AnimalDetailOverviewSection(detail: detail)
        AnimalDetailTagsSection(detail: detail)
        AnimalDetailDistinguishingFeaturesSection(detail: detail)
        AnimalDetailLineageSection(isExpanded: $isLineageExpanded, detail: detail)
        AnimalDetailStatusSection(detail: detail) { status in
            viewModel.beginEditingStatus(status)
        }
        AnimalDetailRecordManagementSection(
            detail: detail,
            hardDeleteOnSwipe: hardDeleteOnSwipe,
            onRestore: { viewModel.restore(animalID: animalID, using: repository) },
            onArchive: { viewModel.archive(animalID: animalID, using: repository) },
            onDelete: { viewModel.delete(animalID: animalID, using: repository) }
        )
    }

}
