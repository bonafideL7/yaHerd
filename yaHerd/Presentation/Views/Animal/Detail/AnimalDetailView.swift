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
    @State private var showingArchiveConfirmation = false
    @State private var showingHardDeleteConfirmation = false
    @State private var showingError = false
    @State private var showingAddTag = false
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
                viewModel.addTag(
                    animalID: animalID,
                    number: number,
                    colorID: colorID,
                    isPrimary: isPrimary,
                    using: repository
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
        return viewModel.form.draft.hasChanges(comparedTo: detail)
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
            tagDetail: viewModel.detail,
            tagActions: AnimalTagManagementActions(
                onAdd: { _, _, _ in },
                onPromote: { tagID in
                    viewModel.promoteTag(animalID: animalID, tagID: tagID, using: repository)
                },
                onRetire: { tagID in
                    viewModel.retireTag(animalID: animalID, tagID: tagID, using: repository)
                }
            ),
            pendingTags: nil,
            onAddExistingTag: { showingAddTag = true },
            onAddPendingTag: nil,
            scrollTarget: .status
        )
    }

    @ViewBuilder
    private func readOnlyContent(_ detail: AnimalDetailSnapshot) -> some View {
        overviewSection(detail)
        tagsSection(detail)
        distinguishingFeaturesSection(detail)
        lineageSection(detail)
        statusSection(detail)       
        recordManagementSection(detail)
    }

    @ViewBuilder
    private func overviewSection(_ detail: AnimalDetailSnapshot) -> some View {
        Section("Overview") {

            if !detail.name.isEmpty {
                LabeledContent("Name") {
                    Text(detail.name.nilIfEmpty ?? "—")
                }
            }

            LabeledContent("Birth Date") {
                Text(detail.birthDate.formatted(date: .abbreviated, time: .omitted))
            }

            LabeledContent("Sex") {
                Text(detail.sex.label)
            }

            LabeledContent("Pasture") {
                Text(detail.pastureName ?? "None")
            }
        }
    }
    
    @ViewBuilder
    private func tagsSection(_ detail: AnimalDetailSnapshot) -> some View {
        Section("Tags") {
            if detail.activeTags.isEmpty {
                Text("No active tags")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.activeTags) { tag in
                    tagRow(for: tag)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d.width }
                }
            }
            
        }
    }

    @ViewBuilder
    private func statusSection(_ detail: AnimalDetailSnapshot) -> some View {
        Section("Status") {
            HStack {
                Text("Current Status")
                Spacer()
                Label(detail.status.label, systemImage: detail.status.systemImage)
                    .fontWeight(.semibold)
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .alignmentGuide(.listRowSeparatorTrailing) { d in d.width }

            if let statusReferenceName = detail.statusReferenceName {
                LabeledContent("Status Reference") {
                    Text(statusReferenceName)
                        .fontWeight(.medium)
                }
            }

            if detail.isArchived {
                HStack {
                    Text("Record State")
                    Spacer()
                    Label("Archived", systemImage: "archivebox.fill")
                        .foregroundStyle(.orange)
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .alignmentGuide(.listRowSeparatorTrailing) { d in d.width }

                if let archivedAt = detail.archivedAt {
                    LabeledContent("Archived On") {
                        Text(archivedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }

            switch detail.status {
            case .active:
                EmptyView()
            case .sold:
                LabeledContent("Sale Date") {
                    Text((detail.saleDate ?? .now).formatted(date: .abbreviated, time: .omitted))
                }

                LabeledContent("Sale Price") {
                    Text(
                        detail.salePrice?.formatted(
                            .currency(code: Locale.current.currency?.identifier ?? "USD")
                        ) ?? "—"
                    )
                }

                if let reasonSold = detail.reasonSold, !reasonSold.isEmpty {
                    LabeledContent("Reason Sold") {
                        Text(reasonSold)
                            .multilineTextAlignment(.trailing)
                    }
                }
            case .dead:
                LabeledContent("Death Date") {
                    Text((detail.deathDate ?? .now).formatted(date: .abbreviated, time: .omitted))
                }

                if let causeOfDeath = detail.causeOfDeath, !causeOfDeath.isEmpty {
                    LabeledContent("Cause of Death") {
                        Text(causeOfDeath)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            statusActionButtons(detail)
        }
    }

    @ViewBuilder
    private func statusActionButtons(_ detail: AnimalDetailSnapshot) -> some View {
        switch detail.status {
        case .active:
            Button {
                viewModel.beginEditingStatus(.sold)
            } label: {
                Label("Mark Sold", systemImage: AnimalStatus.sold.systemImage)
            }

            Button {
                viewModel.beginEditingStatus(.dead)
            } label: {
                Label("Mark Dead", systemImage: AnimalStatus.dead.systemImage)
            }

        case .sold:
            Button {
                viewModel.beginEditingStatus(.active)
            } label: {
                Label("Return to Active", systemImage: AnimalStatus.active.systemImage)
            }

            Button {
                viewModel.beginEditingStatus(.dead)
            } label: {
                Label("Correct to Dead", systemImage: AnimalStatus.dead.systemImage)
            }

        case .dead:
            Button {
                viewModel.beginEditingStatus(.active)
            } label: {
                Label("Correct to Active", systemImage: AnimalStatus.active.systemImage)
            }

            Button {
                viewModel.beginEditingStatus(.sold)
            } label: {
                Label("Correct to Sold", systemImage: AnimalStatus.sold.systemImage)
            }
        }
    }
    
    @ViewBuilder
    private func lineageSection(_ detail: AnimalDetailSnapshot) -> some View {
        let dam = detail.dam?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sire = detail.sire?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let hasDam = !(dam ?? "").isEmpty
        let hasSire = !(sire ?? "").isEmpty
        let hasLineage = hasDam || hasSire
        
        if hasLineage {
            Section {
                DisclosureGroup("Parents", isExpanded: $isLineageExpanded) {
                    if let dam, !dam.isEmpty {
                        LabeledContent("Dam") {
                            Text(dam)
                        }
                    }
                    
                    if let sire, !sire.isEmpty {
                        LabeledContent("Sire") {
                            Text(sire)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func distinguishingFeaturesSection(_ detail: AnimalDetailSnapshot) -> some View {
        if !detail.distinguishingFeatures.isEmpty {
            Section("Distinguishing Features") {
                ForEach(detail.distinguishingFeatures) { feature in
                    Text(feature.description)
                }
            }
        }
    }

    @ViewBuilder
    private func recordManagementSection(_ detail: AnimalDetailSnapshot) -> some View {
        Section {
            if detail.isArchived {
                Button {
                    viewModel.restore(animalID: animalID, using: repository)
                } label: {
                    Label("Restore Archived Record", systemImage: "arrow.uturn.backward.circle.fill")
                }
            } else {
                Button(role: .destructive) {
                    showingArchiveConfirmation = true
                } label: {
                    Label("Archive Record", systemImage: "archivebox")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .confirmationDialog(
                            "Archive this record?",
                            isPresented: $showingArchiveConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Archive Record", role: .destructive) {
                                viewModel.archive(animalID: animalID, using: repository)
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Archived records are hidden from normal herd views but can be restored later.")
                        }
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
            }.alert("Permanently delete this animal?", isPresented: $showingHardDeleteConfirmation) {
                Button("Delete Permanently", role: .destructive) {
                    viewModel.delete(animalID: animalID, using: repository)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the animal and all related records from the app.")
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
    private func tagRow(for tag: AnimalTagSnapshot) -> some View {
        HStack {
            tagBadge(for: tag)
            Spacer()
            if tag.isPrimary {
                Label("Primary", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

private struct AnimalTimelineContainerView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    let animalID: UUID

    @State private var events: [AnimalTimelineEvent] = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if hasLoaded {
                if events.isEmpty {
                    ContentUnavailableView("Timeline Unavailable", systemImage: "clock.arrow.circlepath")
                } else {
                    AnimalTimelineView(events: events)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard !hasLoaded else { return }
            events = (try? dependencies.animalRepository.fetchTimeline(id: animalID)) ?? []
            hasLoaded = true
        }
    }
}
