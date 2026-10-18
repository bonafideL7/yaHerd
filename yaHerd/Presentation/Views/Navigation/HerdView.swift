import SwiftUI

enum HerdViewMode: String, Hashable, Codable {
    case animals
    case pastures
}

struct HerdView: View {
    @Binding private var searchText: String
    @Binding private var isSearchPresented: Bool

    @Binding private var mode: HerdViewMode
    @Environment(\.colorScheme) private var colorScheme
    private let allowsModeSwitch: Bool
    @State private var isManagingPastures = false
    @State private var animalListModel = AnimalListViewModel()
    @State private var pastureListModel = PastureTileListViewModel()

    private let sortOrder: Binding<AnimalSortOrder>?
    private let filter: Binding<AnimalFilter>?
    private let showRemovedStatuses: Binding<Bool>?
    private let showArchivedRecords: Binding<Bool>?
    private let showingFilters: Binding<Bool>?
    private let pastureFilter: Binding<PastureListFilter>?
    private let usesShellBottomAccessory: Bool
    private let onOpenAnimal: (UUID) -> Void
    private let onOpenPasture: (UUID) -> Void
    private let onOpenFieldChecks: () -> Void
    private let onOpenWorkSessions: () -> Void
    private let onOpenSettings: () -> Void

    init(
        searchText: Binding<String> = .constant(""),
        isSearchPresented: Binding<Bool> = .constant(false),
        mode: Binding<HerdViewMode> = .constant(.animals),
        allowsModeSwitch: Bool = true,
        sortOrder: Binding<AnimalSortOrder>? = nil,
        filter: Binding<AnimalFilter>? = nil,
        showRemovedStatuses: Binding<Bool>? = nil,
        showArchivedRecords: Binding<Bool>? = nil,
        showingFilters: Binding<Bool>? = nil,
        pastureFilter: Binding<PastureListFilter>? = nil,
        usesShellBottomAccessory: Bool = false,
        onOpenAnimal: @escaping (UUID) -> Void = { _ in },
        onOpenPasture: @escaping (UUID) -> Void = { _ in },
        onOpenFieldChecks: @escaping () -> Void = {},
        onOpenWorkSessions: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self._searchText = searchText
        self._isSearchPresented = isSearchPresented
        self._mode = mode
        self.allowsModeSwitch = allowsModeSwitch
        self.sortOrder = sortOrder
        self.filter = filter
        self.showRemovedStatuses = showRemovedStatuses
        self.showArchivedRecords = showArchivedRecords
        self.showingFilters = showingFilters
        self.pastureFilter = pastureFilter
        self.usesShellBottomAccessory = usesShellBottomAccessory
        self.onOpenAnimal = onOpenAnimal
        self.onOpenPasture = onOpenPasture
        self.onOpenFieldChecks = onOpenFieldChecks
        self.onOpenWorkSessions = onOpenWorkSessions
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        Group {
            switch mode {
            case .animals:
                AnimalListView(
                    viewModel: animalListModel,
                    searchText: $searchText,
                    isSearching: $isSearchPresented,
                    sortOrder: sortOrder,
                    filter: filter,
                    showRemovedStatuses: showRemovedStatuses,
                    showArchivedRecords: showArchivedRecords,
                    showingFilters: showingFilters,
                    usesExternalSearchField: true,
                    hidesControlsUntilSearch: true,
                    usesShellBottomAccessory: usesShellBottomAccessory,
                    onOpenAnimal: onOpenAnimal,
                    onOpenFieldChecks: onOpenFieldChecks,
                    onOpenWorkSessions: onOpenWorkSessions,
                    onOpenSettings: onOpenSettings
                )
            case .pastures:
                PastureTileListView(
                    model: pastureListModel,
                    isManaging: $isManagingPastures,
                    filter: pastureFilter,
                    onOpenPasture: onOpenPasture,
                    onOpenFieldChecks: onOpenFieldChecks,
                    onOpenWorkSessions: onOpenWorkSessions,
                    onOpenSettings: onOpenSettings
                )
            }
        }
        .navigationTitle(allowsModeSwitch ? (mode == .animals ? "Animals" : "Pastures") : "Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsModeSwitch {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        switchMode()
                    } label: {
                        Image(systemName: switchButtonSystemImage)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background {
                                Circle()
                                    .fill(.regularMaterial)
                                    .overlay {
                                        Circle().fill(
                                            Color.accentColor.opacity(colorScheme == .dark ? 0.26 : 0.18)
                                        )
                                    }
                                    .overlay {
                                        Circle().strokeBorder(
                                            Color.accentColor.opacity(colorScheme == .dark ? 0.45 : 0.30),
                                            lineWidth: 1
                                        )
                                    }
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(switchButtonAccessibilityLabel)
                }
                .sharedBackgroundVisibility(.hidden)
            }
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

    private var switchButtonAccessibilityLabel: String {
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
