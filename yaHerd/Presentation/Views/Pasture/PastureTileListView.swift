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
                ContentUnavailableView(
                    "No pastures",
                    systemImage: "leaf",
                    description: Text("Add a pasture to start tracking acreage and stocking.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.items) { pasture in
                            PastureTileCard(pasture: pasture) {
                                selectedPasture = pasture
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Pastures")
        .navigationDestination(item: $selectedPasture) { pasture in
            PastureDetailView(pastureID: pasture.id)
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
