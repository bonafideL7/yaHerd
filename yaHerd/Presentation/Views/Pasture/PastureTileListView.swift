import SwiftUI
import UniformTypeIdentifiers

struct PastureTileListView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var model = PastureTileListViewModel()
    @State private var selectedPasture: PastureSummary?
    @State private var isPresentingAddPasture = false
    @State private var internalFilter: PastureListFilter = .all
    @State private var draggedPasture: PastureSummary?
    @State private var dragStartOrder: [PastureSummary] = []
    @State private var pasturePendingDeletion: PastureSummary?

    @Binding private var isManaging: Bool

    private let repository: any PastureRepository
    private let animalRepository: any AnimalPastureMoving
    private let fieldCheckRepository: any FieldCheckPastureCleanupWriter
    private let externalFilter: Binding<PastureListFilter>?
    private let onOpenSettings: () -> Void
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    init(
        repository: any PastureRepository,
        animalRepository: any AnimalPastureMoving,
        fieldCheckRepository: any FieldCheckPastureCleanupWriter,
        isManaging: Binding<Bool>,
        filter: Binding<PastureListFilter>? = nil,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.animalRepository = animalRepository
        self.fieldCheckRepository = fieldCheckRepository
        self._isManaging = isManaging
        self.externalFilter = filter
        self.onOpenSettings = onOpenSettings
    }

    private var filterBinding: Binding<PastureListFilter> {
        Binding {
            externalFilter?.wrappedValue ?? internalFilter
        } set: { newValue in
            if let externalFilter {
                externalFilter.wrappedValue = newValue
            } else {
                internalFilter = newValue
            }
        }
    }

    private var filterValue: PastureListFilter {
        filterBinding.wrappedValue
    }

    private var filteredItems: [PastureSummary] {
        switch filterValue {
        case .all:
            return model.items
        case .overCapacity:
            return model.items.filter(\.isOverCapacity)
        case .underutilized:
            return model.items.filter(\.isUnderutilized)
        case .rotationReady:
            return model.items.filter(\.isRotationReady)
        case .missingStockingData:
            return model.items.filter(\.isMissingStockingData)
        }
    }

    var body: some View {
        Group {
            if model.items.isEmpty {
                emptyState
            } else if isManaging {
                manageGrid
            } else if filteredItems.isEmpty {
                noMatchesState
            } else {
                tileGrid
            }
        }
        .navigationDestination(item: $selectedPasture) { pasture in
            PastureDetailView(pastureID: pasture.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                pastureToolbarAction
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: 88)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if !isManaging {
                addPastureButton
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $isPresentingAddPasture) {
            AddPastureView {
                model.load(using: repository)
            }
        }
        .confirmationDialog(
            "Delete Pasture?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            if let pasture = pasturePendingDeletion {
                Button("Delete \(pasture.name)", role: .destructive) {
                    withAnimation(.snappy) {
                        model.deletePasture(
                            id: pasture.id,
                            pastureRepository: repository,
                            animalRepository: animalRepository,
                            fieldCheckRepository: fieldCheckRepository
                        )
                    }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            if let pasture = pasturePendingDeletion {
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No pastures", systemImage: "leaf")
        } description: {
            Text("Add a pasture to start tracking acreage and stocking.")
        } actions: {
            Button("Add Pasture") {
                isPresentingAddPasture = true
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(colorScheme == .dark ? .black : .white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addPastureButton: some View {
        Button {
            isPresentingAddPasture = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        }
        .accessibilityLabel("Add Pasture")
    }

    @ViewBuilder
    private var pastureToolbarAction: some View {
        if isManaging {
            Button {
                toggleManageMode()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Done Managing")
        } else {
            Menu {
                Button {
                    toggleManageMode()
                } label: {
                    Label("Manage Pastures", systemImage: "line.3.horizontal.decrease.circle")
                }

                Divider()

                Picker("Filter", selection: filterBinding) {
                    ForEach(PastureListFilter.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }

                if filterValue != .all {
                    Button {
                        filterBinding.wrappedValue = .all
                    } label: {
                        Label("Clear Filter", systemImage: "xmark.circle")
                    }
                }

                Divider()

                NavigationLink {
                    FieldChecksView(mode: .all)
                } label: {
                    Label("Pasture Checks", systemImage: "checklist")
                }

                NavigationLink {
                    WorkingSessionsView()
                } label: {
                    Label("Working Sessions", systemImage: "wrench.and.screwdriver")
                }

                Divider()

                Button {
                    onOpenSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                toolbarMenuLabel
            }
            .accessibilityLabel("Pasture list actions")
        }
    }

    private var toolbarMenuLabel: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private var tileGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if filterValue != .all {
                    filterSummaryRow
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filteredItems) { pasture in
                        PastureTileCard(pasture: pasture) {
                            selectedPasture = pasture
                        }
                        .onLongPressGesture(minimumDuration: 0.35) {
                            withAnimation(.snappy) {
                                isManaging = true
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var manageGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.items) { pasture in
                        PastureTileCard(
                            pasture: pasture,
                            isManaging: true,
                            isDragging: draggedPasture?.id == pasture.id,
                            onDelete: {
                                pasturePendingDeletion = pasture
                            },
                            onTap: {}
                        )
                        .onDrag {
                            dragStartOrder = model.items
                            draggedPasture = pasture
                            return NSItemProvider(object: pasture.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PastureTileDropDelegate(
                                pasture: pasture,
                                items: model.items,
                                draggedPasture: $draggedPasture,
                                movePasture: { source, destination in
                                    withAnimation(.snappy) {
                                        model.movePasturesInMemory(
                                            from: IndexSet(integer: source),
                                            to: destination
                                        )
                                    }
                                },
                                commitPastureOrder: {
                                    if !dragStartOrder.isEmpty {
                                        model.commitPastureOrder(using: repository, rollbackTo: dragStartOrder)
                                    }
                                    dragStartOrder = []
                                }
                            )
                        )
                        .zIndex(draggedPasture?.id == pasture.id ? 1 : 0)
                    }
                }
            }
            .padding(16)
        }
    }

    private var noMatchesState: some View {
        ContentUnavailableView {
            Label("No Matching Pastures", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No pastures match the \(filterValue.label.lowercased()) filter.")
        } actions: {
            Button("Clear Filter") {
                filterBinding.wrappedValue = .all
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var filterSummaryRow: some View {
        HStack(spacing: 10) {
            Label(filterValue.label, systemImage: "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.semibold))

            Text("\(filteredItems.count) of \(model.items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Clear") {
                filterBinding.wrappedValue = .all
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    model.errorMessage = nil
                }
            }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pasturePendingDeletion != nil },
            set: { newValue in
                if !newValue {
                    pasturePendingDeletion = nil
                }
            }
        )
    }
}

private struct PastureTileDropDelegate: DropDelegate {
    let pasture: PastureSummary
    let items: [PastureSummary]
    @Binding var draggedPasture: PastureSummary?
    let movePasture: (Int, Int) -> Void
    let commitPastureOrder: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedPasture,
              draggedPasture.id != pasture.id,
              let sourceIndex = items.firstIndex(where: { $0.id == draggedPasture.id }),
              let destinationIndex = items.firstIndex(where: { $0.id == pasture.id }) else {
            return
        }

        let destination = sourceIndex < destinationIndex ? destinationIndex + 1 : destinationIndex
        movePasture(sourceIndex, destination)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggedPasture != nil else { return false }

        commitPastureOrder()
        draggedPasture = nil
        return true
    }
}
