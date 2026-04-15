import SwiftUI

struct DashboardPastureListView: View {

    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    @State private var viewModel = DashboardPastureListViewModel()
    @State private var filter: DashboardPastureFilter = .all

    private let repository: any DashboardRepository

    init(repository: any DashboardRepository) {
        self.repository = repository
    }

    private var configuration: DashboardConfiguration {
        DashboardConfiguration(
            pregnancyCheckIntervalDays: pregCheckIntervalDays,
            treatmentIntervalDays: treatmentIntervalDays,
            enablePastureOverstockWarnings: enablePastureOverstockWarnings,
            fallbackPastureCapacity: pastureCapacity
        )
    }

    private var configurationSignature: String {
        [
            String(configuration.pregnancyCheckIntervalDays),
            String(configuration.treatmentIntervalDays),
            String(configuration.enablePastureOverstockWarnings),
            String(configuration.fallbackPastureCapacity)
        ].joined(separator: ":")
    }

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
        .onChange(of: configurationSignature) { _, _ in
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

                if pasture.isOverstocked {
                    Label("Over", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
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
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let capacity = pasture.capacityHead, capacity > 0 {
                ProgressView(value: Double(pasture.activeAnimalCount), total: capacity)
            }
        }
    }
}
