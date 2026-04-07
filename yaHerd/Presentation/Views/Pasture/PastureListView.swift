import SwiftData
import SwiftUI

struct PastureListView: View {
    @Environment(\.modelContext) private var context

    @State private var model = PastureListViewModel()

    private var repository: any PastureRepository {
        SwiftDataPastureRepository(context: context)
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                if model.items.isEmpty {
                    ContentUnavailableView(
                        "No pastures",
                        systemImage: "leaf",
                        description: Text("Add a pasture to start tracking acreage and stocking.")
                    )
                } else {
                    ForEach(model.items) { pasture in
                        NavigationLink(value: pasture) {
                            pastureRow(pasture)
                        }
                    }
                    .onDelete { offsets in
                        model.delete(at: offsets, using: repository)
                    }
                }
            }
            .navigationTitle("Pastures")
            .navigationDestination(for: PastureSummary.self) { pasture in
                PastureDetailView(pastureID: pasture.id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.isPresentingAddPasture = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $model.isPresentingAddPasture) {
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
    }

    private func pastureRow(_ pasture: PastureSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pasture.name)
                .font(.headline)

            if let acreage = pasture.acreage {
                Text("\(acreage.formatted()) acres")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Animals: \(pasture.activeAnimalCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
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
