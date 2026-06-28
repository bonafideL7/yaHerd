import SwiftUI

struct PastureTileListView: View {
    @Environment(\.pastureListRepository) private var repository
    @Environment(\.animalPastureMover) private var animalMover
    @Environment(\.fieldCheckPastureCleanupWriter) private var fieldCheckCleanupWriter

    @State private var model = PastureTileListViewModel()
    @Binding private var isManaging: Bool

    private let externalFilter: Binding<PastureListFilter>?
    private let onOpenSettings: () -> Void

    init(
        isManaging: Binding<Bool>,
        filter: Binding<PastureListFilter>? = nil,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self._isManaging = isManaging
        self.externalFilter = filter
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
        model.filteredItems(for: filterValue)
    }

    var body: some View {
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
                }
            } else {
                PastureTileGrid(
                    items: filteredItems,
                    filter: filterValue,
                    totalCount: model.items.count,
                    onSelect: model.select,
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
            if !isManaging {
                PastureAddButton(onAddPasture: model.requestAddPasture)
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $model.isPresentingAddPasture) {
            AddPastureView {
                model.load(using: repository)
            }
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
                            fieldCheckRepository: fieldCheckCleanupWriter
                        )
                    }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            if let pasture = model.pasturePendingDeletion {
                Text("This will permanently delete \(pasture.name). This action can’t be undone.")
            } else {
                Text("This action can’t be undone.")
            }
        }
        .task {
            model.load(using: repository)
        }
        .alert("Can’t Complete Request", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private func toggleManageMode() {
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
}
