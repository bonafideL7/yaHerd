import SwiftData
import SwiftUI

struct DashboardPastureListView: View {
    @Environment(\.modelContext) private var context

    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    @Query private var animals: [Animal]
    @Query private var pastures: [Pasture]

    @State private var viewModel = DashboardPastureListViewModel()
    @State private var filter: DashboardPastureFilter = .all

    private var repository: any DashboardRepository {
        SwiftDataDashboardRepository(context: context)
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


    private var reloadKey: String {
        [
            configurationSignature,
            animalObservationSignature,
            pastureObservationSignature
        ].joined(separator: "|")
    }

    private var animalObservationSignature: String {
        animals
            .sorted { $0.publicID.uuidString < $1.publicID.uuidString }
            .map { animal in
                [
                    animal.publicID.uuidString,
                    animal.status.rawValue,
                    String(animal.isArchived),
                    animal.pasture?.publicID.uuidString ?? "nil"
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    private var pastureObservationSignature: String {
        let sortedPastures = pastures.sorted { $0.publicID.uuidString < $1.publicID.uuidString }
        let signatures = sortedPastures.map(pastureSignature)
        return signatures.joined(separator: "|")
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
        .task(id: reloadKey) {
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

    private func pastureSignature(_ pasture: Pasture) -> String {
        [
            pasture.publicID.uuidString,
            pasture.name,
            formattedDateString(pasture.lastGrazedDate),
            formattedDoubleString(pasture.acreage),
            formattedDoubleString(pasture.usableAcreage),
            formattedDoubleString(pasture.targetAcresPerHead)
        ].joined(separator: ":")
    }

    private func formattedDateString(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return date.formatted(date: .numeric, time: .standard)
    }

    private func formattedDoubleString(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(value)
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
