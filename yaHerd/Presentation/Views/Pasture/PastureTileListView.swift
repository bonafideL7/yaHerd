import SwiftUI

struct PastureTileListView: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.pastureFeatureDependencies) private var pastureDependencies
    @Environment(\.animalFeatureDependencies) private var animalDependencies
    @Environment(AppNavigationState.self) private var navigation
    private var repository: any PastureListRepository { pastureDependencies.listRepository }
    private var animalMover: any AnimalPastureMoving { pastureDependencies.animalMover }
    private var fieldCheckArchiveWriter: any FieldCheckPastureArchiveWriter { pastureDependencies.fieldCheckArchiveWriter }
    private var animalQueryReader: any AnimalListQueryReading { animalDependencies.listQueryReader }
    @Environment(\.appDataAccessMode) private var dataAccessMode

    @State private var model = PastureTileListViewModel()
    @Binding private var isManaging: Bool

    private let externalFilter: Binding<PastureListFilter>?
    private let onOpenPasture: ((UUID) -> Void)?
    private let onOpenFieldChecks: () -> Void
    private let onOpenWorkSessions: () -> Void
    private let onOpenSettings: () -> Void

    init(
        isManaging: Binding<Bool>,
        filter: Binding<PastureListFilter>? = nil,
        onOpenPasture: ((UUID) -> Void)? = nil,
        onOpenFieldChecks: @escaping () -> Void = {},
        onOpenWorkSessions: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self._isManaging = isManaging
        self.externalFilter = filter
        self.onOpenPasture = onOpenPasture
        self.onOpenFieldChecks = onOpenFieldChecks
        self.onOpenWorkSessions = onOpenWorkSessions
        self.onOpenSettings = onOpenSettings
    }

    private var filterBinding: Binding<PastureListFilter> {
        Binding {
            externalFilter?.wrappedValue ?? model.internalFilter
        } set: { newValue in
            if let externalFilter {
                externalFilter.wrappedValue = newValue
            } else {
                model.internalFilter = newValue
            }
        }
    }

    private var filterValue: PastureListFilter {
        filterBinding.wrappedValue
    }

    private var filteredItems: [PastureSummary] {
        model.filteredItems(
            for: filterValue,
            query: navigation.animalQuery.query,
            formatTag: tagColorLibrary.formattedTag(tagNumber:colorID:)
        )
    }

    private var filterPastureOptions: [PastureOption] {
        model.items.map { PastureOption(id: $0.id, name: $0.name) }
    }

    var body: some View {
        @Bindable var query = navigation.animalQuery

        Group {
            if model.items.isEmpty {
                PastureEmptyStateView(onAddPasture: model.requestAddPasture)
            } else if isManaging {
                PastureManageGrid(
                    items: model.items,
                    draggedPasture: $model.draggedPasture,
                    onDelete: model.requestDelete,
                    onBeginDrag: model.beginDragging,
                    onMove: { source, destination in
                        withAnimation(.snappy) {
                            model.moveDraggedPasture(from: source, to: destination)
                        }
                    },
                    onCommitMove: {
                        model.commitDragOrder(using: repository)
                    }
                )
            } else if filteredItems.isEmpty {
                PastureNoMatchesStateView(filter: filterValue) {
                    filterBinding.wrappedValue = .all
                    navigation.animalQuery.clearCriteria()
                }
            } else {
                PastureTileGrid(
                    items: filteredItems,
                    filter: filterValue,
                    totalCount: model.items.count,
                    onSelect: openPasture,
                    onBeginManaging: toggleManageMode,
                    onClearFilter: {
                        filterBinding.wrappedValue = .all
                    }
                )
            }
        }
        .navigationDestination(item: $model.selectedPasture) { pasture in
            PastureDetailView(pastureID: pasture.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PastureTileToolbar(
                    filter: filterBinding,
                    isManaging: isManaging,
                    onToggleManageMode: toggleManageMode,
                    onOpenFieldChecks: onOpenFieldChecks,
                    onOpenWorkSessions: onOpenWorkSessions,
                    onOpenSettings: onOpenSettings
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: 88)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if dataAccessMode.allowsDataMutations && !isManaging {
                PastureAddButton(onAddPasture: model.requestAddPasture)
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $model.isPresentingAddPasture) {
            AddPastureView {
                Task { @MainActor in
                    await model.load(
                        using: repository,
                        animalQueryReader: animalQueryReader
                    )
                }
            }
        }
        .sheet(isPresented: $query.showingFilters) {
            AnimalFilterView(
                filter: $query.filter,
                showRemovedStatuses: $query.showRemovedStatuses,
                showArchivedRecords: $query.showArchivedRecords,
                pastureOptions: filterPastureOptions
            )
        }
        .confirmationDialog(
            "Delete Pasture?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            if let pasture = model.pasturePendingDeletion {
                Button("Delete \(pasture.name)", role: .destructive) {
                    withAnimation(.snappy) {
                        model.deletePasture(
                            id: pasture.id,
                            pastureRepository: repository,
                            animalRepository: animalMover,
                            fieldCheckRepository: fieldCheckArchiveWriter
                        )
                    }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            if let pasture = model.pasturePendingDeletion {
                Text("This will permanently delete the pasture record for \(pasture.name). Historical pasture checks will remain available under Archived Pastures.")
            } else {
                Text("Historical pasture checks will remain available under Archived Pastures.")
            }
        }
        .task {
            await model.load(
                using: repository,
                animalQueryReader: animalQueryReader
            )
        }
        .alert("Can’t Complete Request", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private func toggleManageMode() {
        guard dataAccessMode.allowsDataMutations || isManaging else { return }
        withAnimation(.snappy) {
            isManaging.toggle()
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.clearError()
                }
            }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.pasturePendingDeletion != nil },
            set: { newValue in
                if !newValue {
                    model.clearPendingDeletion()
                }
            }
        )
    }

    private func openPasture(_ pasture: PastureSummary) {
        if let onOpenPasture {
            onOpenPasture(pasture.id)
        } else {
            model.select(pasture)
        }
    }
}
