import SwiftUI

struct PastureTileListView: View {
    @Environment(\.pastureFeatureDependencies) private var pastureDependencies
    private var repository: any PastureListManagingRepository { pastureDependencies.listRepository }
    private var deletionCommand: any PastureDeletionPerforming { pastureDependencies.deletionCommand }
    @Environment(\.appDataAccessMode) private var dataAccessMode

    private let model: PastureTileListViewModel
    @Binding private var isManaging: Bool

    private let externalFilter: Binding<PastureListFilter>?
    private let onOpenPasture: ((UUID) -> Void)?
    private let onOpenFieldChecks: () -> Void
    private let onOpenWorkSessions: () -> Void
    private let onOpenSettings: () -> Void

    init(
        model: PastureTileListViewModel = PastureTileListViewModel(),
        isManaging: Binding<Bool>,
        filter: Binding<PastureListFilter>? = nil,
        onOpenPasture: ((UUID) -> Void)? = nil,
        onOpenFieldChecks: @escaping () -> Void = {},
        onOpenWorkSessions: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.model = model
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
        model.filteredItems(for: filterValue)
    }

    var body: some View {
        @Bindable var model = model

        pastureContent(draggedPasture: $model.draggedPasture)
        .disabled(model.isDeletingPastures)
        .navigationDestination(item: $model.selectedPasture) { pasture in
            PastureDetailView(pastureID: pasture.id)
        }
        .toolbar {
            if !isManaging {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter Pastures", selection: filterBinding) {
                            ForEach(PastureListFilter.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        if filterValue != .all {
                            Divider()

                            Button {
                                filterBinding.wrappedValue = .all
                            } label: {
                                Label("Clear Filter", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Label(
                            "Filter",
                            systemImage: filterValue == .all
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill"
                        )
                        .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel(
                        filterValue == .all
                            ? "Filter Pastures"
                            : "Filter Pastures, \(filterValue.label) active"
                    )
                    .disabled(model.isDeletingPastures)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                PastureTileToolbar(
                    isManaging: isManaging,
                    onToggleManageMode: toggleManageMode,
                    onOpenFieldChecks: onOpenFieldChecks,
                    onOpenWorkSessions: onOpenWorkSessions,
                    onOpenSettings: onOpenSettings
                )
                .disabled(model.isDeletingPastures)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: 88)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if dataAccessMode.allowsDataMutations && !isManaging && !model.isDeletingPastures {
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
                    Task { @MainActor in
                        await model.deletePasture(
                            id: pasture.id,
                            deletionCommand: deletionCommand,
                            orderingRepository: repository
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
            await model.observe(
                using: repository,
                mutationStream: pastureDependencies.mutationStream
            )
        }
        .alert("Can’t Complete Request", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func pastureContent(draggedPasture: Binding<PastureSummary?>) -> some View {
        if !model.hasLoaded {
            initialContentView
        } else if model.items.isEmpty {
            PastureEmptyStateView(onAddPasture: model.requestAddPasture)
        } else if isManaging {
            PastureManageGrid(
                items: model.items,
                draggedPasture: draggedPasture,
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
                onSelect: openPasture,
                onBeginManaging: toggleManageMode,
                onClearFilter: {
                    filterBinding.wrappedValue = .all
                }
            )
        }
    }

    @ViewBuilder
    private var initialContentView: some View {
        if model.hasInitialLoadFailure {
            ContentUnavailableView {
                Label("Unable to Load Pastures", systemImage: "exclamationmark.triangle")
            } description: {
                Text("The pasture list could not be loaded.")
            } actions: {
                Button {
                    _ = model.load(using: repository)
                } label: {
                    Text("Try Again")
                        .readableForeground(on: .accentColor)
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView("Loading Pastures")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
