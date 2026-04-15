import SwiftUI

struct DashboardAnimalListView: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    @State private var viewModel = DashboardAnimalListViewModel()

    let kind: DashboardAnimalListKind
    private let repository: any DashboardRepository

    init(kind: DashboardAnimalListKind, repository: any DashboardRepository) {
        self.kind = kind
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
        .task {
            viewModel.load(kind: kind, configuration: configuration, using: repository)
        }
        .onChange(of: configurationSignature) { _, _ in
            viewModel.load(kind: kind, configuration: configuration, using: repository)
        }
        .onAppear {
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
