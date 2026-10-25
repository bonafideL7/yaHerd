//
//  AnimalDetailView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI

struct AnimalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.animalFeatureDependencies) private var animalDependencies
    private var repository: any AnimalDetailRepository { animalDependencies.detailRepository }
    private var pastureReferenceDataReader: any PastureReferenceDataReader { animalDependencies.pastureReferenceReader }
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @State private var viewModel = AnimalDetailViewModel()
    @State private var activeParentPicker: ParentPickerType?
    @State private var showingError = false
    @State private var showingAddTag = false
    @State private var editingTag: AnimalTagSnapshot?
    @State private var isLineageExpanded = false
    @State private var showingAddOffspring = false
    @State private var showingDiscardConfirmation = false
    @State private var showingArchiveConfirmation = false
    @State private var permanentDeleteReviewDetail: AnimalDetailSnapshot?
    @State private var returnsToListAfterSave: Bool
    @State private var discardDestination: EditingExit = .back

    private enum EditingExit {
        case back
        case details
    }

    let animalID: UUID
    let initiallyEditing: Bool
    let onClose: (() -> Void)?

    init(animalID: UUID, initiallyEditing: Bool = false, onClose: (() -> Void)? = nil) {
        self.animalID = animalID
        self.initiallyEditing = initiallyEditing
        self.onClose = onClose
        _returnsToListAfterSave = State(initialValue: initiallyEditing)
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
        .sheet(isPresented: $showingAddOffspring, onDismiss: {
            viewModel.load(animalID: animalID, using: repository, pastureRepository: pastureReferenceDataReader)
        }) {
            if let preparedEditor = viewModel.preparedOffspringEditor {
                AddAnimalView(
                    title: "Add Offspring",
                    initialDraft: preparedEditor.draft,
                    editorContext: preparedEditor.context
                )
            }
        }
        .alert("Can’t Save", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Discard unsaved changes?", isPresented: $showingDiscardConfirmation) {
            Button("Discard Changes", role: .destructive) {
                finishEditing(discardDestination)
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Changes to this animal have not been saved.")
        }
        .confirmationDialog(
            "Archive this record?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Record", role: .destructive) {
                archiveFromEditor()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived records are hidden from normal herd views but can be restored later.")
        }
        .sheet(item: $permanentDeleteReviewDetail) { reviewDetail in
            AnimalPermanentDeleteReviewView(detail: reviewDetail) {
                viewModel.delete(animalID: animalID, using: repository)
            }
            .presentationDetents([.large])
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isEditing {
                Color.clear.frame(height: 88).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.isEditing {
                floatingActions
                    .padding(.trailing, 24)
                    .padding(.bottom, 12)
            }
        }
        .navigationTitle("Animal")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .accessibilityHint("Return to the previous screen")
            }

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
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarSaveButton {
                        saveChanges()
                    }
                    .disabled(!canSaveChanges)
                }
            }

            if viewModel.detail != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AnimalTimelineContainerView(animalID: animalID)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Animal Timeline")
                }

                if !viewModel.isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        ToolbarEditButton {
                            returnsToListAfterSave = false
                            viewModel.beginEditing()
                        }
                    }
                }
            }
        }
        .task {
            if !viewModel.hasLoaded {
                viewModel.load(animalID: animalID, using: repository, pastureRepository: pastureReferenceDataReader)
                if initiallyEditing && dataAccessMode.allowsDataMutations && viewModel.detail != nil {
                    viewModel.beginEditing()
                }
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showingError = newValue != nil
        }
        .onChange(of: viewModel.didDelete) { _, didDelete in
            if didDelete {
                closeDestination()
            }
        }
    }

    private func closeDestination() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func requestBack() {
        if viewModel.isEditing && canSaveChanges {
            discardDestination = .back
            showingDiscardConfirmation = true
        } else {
            closeDestination()
        }
    }

    private func requestViewDetails() {
        guard viewModel.isEditing else { return }
        if canSaveChanges {
            discardDestination = .details
            showingDiscardConfirmation = true
        } else {
            finishEditing(.details)
        }
    }

    private func finishEditing(_ destination: EditingExit) {
        switch destination {
        case .back:
            closeDestination()
        case .details:
            viewModel.cancelEditing()
            returnsToListAfterSave = false
        }
    }

    private func saveChanges() {
        viewModel.save(
            animalID: animalID,
            defaultTagColorID: tagColorLibrary.defaultColorID,
            using: repository
        )
        if !viewModel.isEditing && returnsToListAfterSave {
            closeDestination()
        }
    }

    private func archiveFromEditor() {
        viewModel.archive(
            animalID: animalID,
            using: repository,
            pastureRepository: pastureReferenceDataReader
        )
        if viewModel.errorMessage == nil {
            viewModel.cancelEditing()
            if returnsToListAfterSave {
                closeDestination()
            }
        }
    }

    private func restoreFromEditor() {
        viewModel.restore(
            animalID: animalID,
            using: repository,
            pastureRepository: pastureReferenceDataReader
        )
        if viewModel.errorMessage == nil {
            viewModel.cancelEditing()
            if returnsToListAfterSave {
                closeDestination()
            }
        }
    }

    private var floatingActions: some View {
        Menu {
            Button {
                requestViewDetails()
            } label: {
                Label("View Details", systemImage: "info.circle")
            }

            if viewModel.canAddOffspring && viewModel.preparedOffspringEditor != nil {
                Button {
                    showingAddOffspring = true
                } label: {
                    Label("Add Offspring", systemImage: "plus.circle")
                }
                .disabled(canSaveChanges)
            }

            if let detail = viewModel.detail, dataAccessMode.allowsDataMutations {
                Divider()

                if detail.isArchived {
                    Button {
                        restoreFromEditor()
                    } label: {
                        Label("Restore Archived Record", systemImage: "arrow.uturn.backward.circle")
                    }
                    .disabled(canSaveChanges)

                    Button(role: .destructive) {
                        permanentDeleteReviewDetail = viewModel.preparePermanentDeleteReview(
                            animalID: animalID,
                            using: repository
                        )
                    } label: {
                        Label("Permanently Delete", systemImage: "trash")
                    }
                    .disabled(canSaveChanges)
                } else {
                    Button(role: .destructive) {
                        showingArchiveConfirmation = true
                    } label: {
                        Label("Archive Record", systemImage: "archivebox")
                    }
                    .disabled(canSaveChanges)
                }
            }
        } label: {
            FloatingAddButtonLabel()
        }
        .accessibilityLabel("Animal actions")
    }

    private var canSaveChanges: Bool {
        guard let detail = viewModel.detail else { return false }
        let draftChanged = viewModel.form.draft.hasChanges(comparedTo: detail)
        let tagChanged = viewModel.draftTags != (detail.activeTags + detail.inactiveTags)
        return draftChanged || tagChanged
    }

    private func scrollFormIfNeeded(using proxy: ScrollViewProxy) {
        guard viewModel.isEditing, let target = viewModel.pendingScrollTarget else { return }
        Task { @MainActor in
            await Task.yield()
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
            editorContext: viewModel.form.context,
            pastures: viewModel.form.pastureOptions,
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
        AnimalDetailOffspringSection(
            detail: detail,
            canAddOffspring: dataAccessMode.allowsDataMutations
                && viewModel.canAddOffspring
                && viewModel.preparedOffspringEditor != nil,
            onAddOffspring: { showingAddOffspring = true }
        )
        AnimalDetailLineageSection(isExpanded: $isLineageExpanded, detail: detail)
        AnimalDetailStatusSection(detail: detail) { status in
            guard dataAccessMode.allowsDataMutations else { return }
            returnsToListAfterSave = false
            viewModel.beginEditingStatus(status)
        }
        AnimalDetailRecordManagementSection(
            detail: detail,
            onRestore: { viewModel.restore(animalID: animalID, using: repository, pastureRepository: pastureReferenceDataReader) },
            onArchive: { viewModel.archive(animalID: animalID, using: repository, pastureRepository: pastureReferenceDataReader) },
            onPreparePermanentDelete: { viewModel.preparePermanentDeleteReview(animalID: animalID, using: repository) },
            onDelete: { viewModel.delete(animalID: animalID, using: repository) }
        )
    }
}
