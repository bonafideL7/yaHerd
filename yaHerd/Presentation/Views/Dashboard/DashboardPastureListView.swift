import SwiftUI

struct DashboardPastureListView: View {

    @State private var viewModel = DashboardPastureListViewModel()
    @State private var filter: DashboardPastureFilter = .all

    private let repository: any DashboardReadWriting

    init(repository: any DashboardReadWriting, initialFilter: DashboardPastureFilter = .all) {
        self.repository = repository
        _filter = State(initialValue: initialFilter)
    }

    private let configuration = DashboardConfiguration()

    private var filteredPastures: [DashboardPastureItem] {
        viewModel.filteredItems(filter)
    }

    var body: some View {
        List {
            Section {
                Picker("Pastures", selection: $filter) {
                    ForEach(DashboardPastureFilter.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if filteredPastures.isEmpty {
                    Text("No matching pastures.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredPastures) { pasture in
                        NavigationLink(value: DashboardRoute.pasture(pasture.id)) {
                            pastureRow(pasture)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                viewModel.markPastureGrazedToday(
                                    pastureID: pasture.id,
                                    configuration: configuration,
                                    using: repository
                                )
                            } label: {
                                Label("Grazed today", systemImage: "calendar")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle("Pastures")
        .task {
            viewModel.load(configuration: configuration, using: repository)
        }
        .onAppear {
            viewModel.load(configuration: configuration, using: repository)
        }
        .alert("Dashboard Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private func pastureRow(_ pasture: DashboardPastureItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pasture.name)
                    .font(.headline)

                Spacer()

                if pasture.isRotationReady {
                    Label("Ready", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if pasture.isUnderutilized {
                    Label("Low", systemImage: "arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text("\(pasture.activeAnimalCount) head")
                if pasture.acres > 0 {
                    Text("• \(pasture.acres.formatted(.number.precision(.fractionLength(0...1)))) ac")
                }
                if let capacity = pasture.capacityHead {
                    Text("• cap \(Int(capacity))")
                }
                if let lastGrazedDate = pasture.lastGrazedDate {
                    Text("• grazed \(lastGrazedDate.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let capacity = pasture.capacityHead, capacity > 0 {
                ProgressView(value: min(max(Double(pasture.activeAnimalCount), 0), capacity), total: capacity)
            }
        }
    }
}
