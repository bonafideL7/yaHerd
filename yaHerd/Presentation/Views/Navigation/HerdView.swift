import SwiftUI

private enum HerdViewMode {
    case animals
    case pastures
}

struct HerdView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    @State private var mode: HerdViewMode = .animals
    @State private var isManagingPastures = false
    @State private var isPresentingAddPasture = false
    @State private var pastureReloadID = UUID()

    var body: some View {
        Group {
            switch mode {
            case .animals:
                AnimalListView()
            case .pastures:
                PastureTileListView(
                    repository: dependencies.pastureRepository,
                    isManaging: $isManagingPastures,
                    reloadID: pastureReloadID
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if mode == .pastures && isManagingPastures {
                    Button {
                        isPresentingAddPasture = true
                    } label: {
                        Label("Add Pasture", systemImage: "plus")
                    }
                    .accessibilityLabel("Add Pasture")
                } else {
                    Button {
                        switchMode()
                    } label: {
                        Label(switchButtonTitle, systemImage: switchButtonSystemImage)
                    }
                    .accessibilityLabel(switchButtonTitle)
                }
            }
        }
        .sheet(isPresented: $isPresentingAddPasture) {
            AddPastureView {
                pastureReloadID = UUID()
            }
            .environmentObject(dependencies)
        }
    }

    private func switchMode() {
        withAnimation(.snappy) {
            switch mode {
            case .animals:
                mode = .pastures
            case .pastures:
                isManagingPastures = false
                mode = .animals
            }
        }
    }

    private var switchButtonTitle: String {
        switch mode {
        case .animals:
            return "Show Pastures"
        case .pastures:
            return "Show Animals"
        }
    }

    private var switchButtonSystemImage: String {
        switch mode {
        case .animals:
            return "leaf"
        case .pastures:
            return "tag"
        }
    }
}
