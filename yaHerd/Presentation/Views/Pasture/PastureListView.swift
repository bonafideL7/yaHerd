import SwiftUI

struct PastureListView: View {
    @State private var model = PastureListViewModel()
    @State private var showingStartPastureCheck = false
    @State private var showingFieldChecks = false

    private let repository: any PastureRepository

    init(repository: any PastureRepository) {
        self.repository = repository
    }

    var body: some View {
        @Bindable var model = model

        List {
            if model.items.isEmpty {
                ContentUnavailableView(
                    "No pastures",
                    systemImage: "leaf",
                    description: Text("Add a pasture to start tracking acreage and stocking.")
                )
            } else {
                Section("Pastures") {
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
        }
        .navigationTitle("Pastures")
        .navigationDestination(for: PastureSummary.self) { pasture in
            PastureDetailView(pastureID: pasture.id)
        }
        .navigationDestination(isPresented: $showingStartPastureCheck) {
            FieldCheckSessionDetailView()
        }
        .navigationDestination(isPresented: $showingFieldChecks) {
            FieldChecksView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        showingStartPastureCheck = true
                    } label: {
                        Label("Start Pasture Check", systemImage: "plus.circle")
                    }

                    Button {
                        showingFieldChecks = true
                    } label: {
                        Label("View Pasture Checks", systemImage: "checklist")
                    }
                } label: {
                    Label("Field Checks", systemImage: "checklist")
                }

                Button {
                    model.isPresentingAddPasture = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Pasture")
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
