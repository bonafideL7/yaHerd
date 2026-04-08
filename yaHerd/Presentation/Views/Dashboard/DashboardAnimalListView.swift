import SwiftData
import SwiftUI

struct DashboardAnimalListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    @Query private var animals: [Animal]
    @Query private var pastures: [Pasture]

    @State private var viewModel = DashboardAnimalListViewModel()

    let kind: DashboardAnimalListKind

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


    private var reloadKey: String {
        [
            kind.rawValue,
            configurationSignature,
            animalObservationSignature,
            pastureObservationSignature
        ].joined(separator: "|")
    }

    private var animalObservationSignature: String {
        animals
            .sorted { $0.publicID.uuidString < $1.publicID.uuidString }
            .map { animal in
                let latestPregnancyCheck = animal.pregnancyChecks.max { lhs, rhs in lhs.date < rhs.date }
                let latestTreatment = animal.healthRecords.max { lhs, rhs in lhs.date < rhs.date }
                return [
                    animal.publicID.uuidString,
                    animal.displayTagNumber,
                    animal.displayTagColorID?.uuidString ?? "nil",
                    animal.status.rawValue,
                    String(animal.isArchived),
                    animal.location.rawValue,
                    animal.pasture?.publicID.uuidString ?? "nil",
                    latestPregnancyCheck?.date.formatted(date: .numeric, time: .standard) ?? "nil",
                    latestTreatment?.date.formatted(date: .numeric, time: .standard) ?? "nil"
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    private var pastureObservationSignature: String {
        pastures
            .sorted { $0.publicID.uuidString < $1.publicID.uuidString }
            .map { pasture in
                [
                    pasture.publicID.uuidString,
                    pasture.name
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    var body: some View {
        List {
            if viewModel.items.isEmpty {
                Text("Nothing to show.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.items) { animal in
                    NavigationLink(value: DashboardRoute.animal(animal.id)) {
                        row(animal)
                    }
                }
            }
        }
        .navigationTitle(kind.title)
        .task(id: reloadKey) {
            viewModel.load(kind: kind, configuration: configuration, using: repository)
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

    private func row(_ animal: DashboardAnimalItem) -> some View {
        HStack(spacing: 12) {
            let definition = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)

            VStack(alignment: .leading, spacing: 6) {
                AnimalTagView(
                    tagNumber: animal.displayTagNumber,
                    color: definition.color,
                    colorName: definition.name
                )

                HStack(spacing: 6) {
                    Text(animal.sex.label)
                    if animal.location == .workingPen {
                        Text("• Working Pen")
                    } else if let pastureName = animal.pastureName {
                        Text("• \(pastureName)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
