import SwiftUI

struct PastureTileListView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var model = PastureTileListViewModel()
    @State private var selectedPasture: PastureSummary?
    @State private var isPresentingAddPasture = false

    @Binding private var isManaging: Bool

    private let repository: any PastureRepository
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    init(
        repository: any PastureRepository,
        isManaging: Binding<Bool>
    ) {
        self.repository = repository
        self._isManaging = isManaging
    }

    var body: some View {
        Group {
            if model.items.isEmpty {
                emptyState
            } else if isManaging {
                manageList
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
            addPastureButton
                .padding(.trailing, 24)
                .padding(.bottom, 24)
        }
        .sheet(isPresented: $isPresentingAddPasture) {
            AddPastureView {
                model.load(using: repository)
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
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(model.items) { pasture in
                    PastureTileCard(pasture: pasture) {
                        selectedPasture = pasture
                    }
                    .onLongPressGesture {
                        withAnimation(.snappy) {
                            isManaging = true
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var manageList: some View {
        List {
            ForEach(model.items) { pasture in
                PastureManageRow(pasture: pasture)
            }
            .onMove { source, destination in
                model.movePastures(from: source, to: destination, using: repository)
            }
            .onDelete { offsets in
                model.deletePastures(at: offsets, using: repository)
            }
        }
        .environment(\.editMode, .constant(.active))
        .listStyle(.insetGrouped)
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
}

private struct PastureManageRow: View {
    let pasture: PastureSummary

    private var acreage: String {
        if let acres = pasture.acreage {
            return acres.formatted()
        }
        return "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pasture.name)
                .font(.headline)

            Text("\(pasture.activeAnimalCount) head • \(acreage) acres")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
