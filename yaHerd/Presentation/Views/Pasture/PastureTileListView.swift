import SwiftUI

struct PastureTileListView: View {
    @State private var model = PastureTileListViewModel()
    @State private var selectedPasture: PastureSummary?

    private let repository: any PastureRepository
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    init(repository: any PastureRepository) {
        self.repository = repository
    }

    var body: some View {
        Group {
            if model.items.isEmpty {
                emptyState
            } else if model.isManaging {
                manageList
            } else {
                tileGrid
            }
        }
        .navigationTitle("Pastures")
        .navigationDestination(item: $selectedPasture) { pasture in
            PastureDetailView(pastureID: pasture.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(model.isManaging ? "Done" : "Manage") {
                    withAnimation(.snappy) {
                        model.toggleManageMode()
                    }
                }
                .disabled(!model.isManaging && model.items.isEmpty)
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
        ContentUnavailableView(
            "No pastures",
            systemImage: "leaf",
            description: Text("Add a pasture to start tracking acreage and stocking.")
        )
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
                            model.enterManageMode()
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
