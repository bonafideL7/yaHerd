import SwiftUI

private enum HerdViewMode {
    case animals
    case pastures
}

struct HerdView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    @State private var mode: HerdViewMode = .animals

    var body: some View {
        Group {
            switch mode {
            case .animals:
                AnimalListView()
            case .pastures:
                PastureTileListView(repository: dependencies.pastureRepository)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) {
                        mode = mode == .animals ? .pastures : .animals
                    }
                } label: {
                    Label(switchButtonTitle, systemImage: switchButtonSystemImage)
                }
                .accessibilityLabel(switchButtonTitle)
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
            return "square.grid.2x2"
        case .pastures:
            return "list.bullet"
        }
    }
}
