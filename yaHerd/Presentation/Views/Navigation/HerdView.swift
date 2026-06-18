import SwiftUI

enum HerdViewMode: Hashable {
    case animals
    case pastures
}

struct HerdView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    @Binding private var searchText: String
    @Binding private var isSearchPresented: Bool

    @Binding private var mode: HerdViewMode
    @State private var isManagingPastures = false

    private let sortOrder: Binding<AnimalSortOrder>?
    private let filter: Binding<AnimalFilter>?
    private let showRemovedStatuses: Binding<Bool>?
    private let showArchivedRecords: Binding<Bool>?
    private let showingFilters: Binding<Bool>?
    private let pastureFilter: Binding<PastureListFilter>?
    private let usesShellBottomAccessory: Bool

    init(
        searchText: Binding<String> = .constant(""),
        isSearchPresented: Binding<Bool> = .constant(false),
        mode: Binding<HerdViewMode> = .constant(.animals),
        sortOrder: Binding<AnimalSortOrder>? = nil,
        filter: Binding<AnimalFilter>? = nil,
        showRemovedStatuses: Binding<Bool>? = nil,
        showArchivedRecords: Binding<Bool>? = nil,
        showingFilters: Binding<Bool>? = nil,
        pastureFilter: Binding<PastureListFilter>? = nil,
        usesShellBottomAccessory: Bool = false
    ) {
        self._searchText = searchText
        self._isSearchPresented = isSearchPresented
        self._mode = mode
        self.sortOrder = sortOrder
        self.filter = filter
        self.showRemovedStatuses = showRemovedStatuses
        self.showArchivedRecords = showArchivedRecords
        self.showingFilters = showingFilters
        self.pastureFilter = pastureFilter
        self.usesShellBottomAccessory = usesShellBottomAccessory
    }

    var body: some View {
        Group {
            switch mode {
            case .animals:
                AnimalListView(
                    searchText: $searchText,
                    isSearching: $isSearchPresented,
                    sortOrder: sortOrder,
                    filter: filter,
                    showRemovedStatuses: showRemovedStatuses,
                    showArchivedRecords: showArchivedRecords,
                    showingFilters: showingFilters,
                    usesExternalSearchField: true,
                    hidesControlsUntilSearch: true,
                    usesShellBottomAccessory: usesShellBottomAccessory
                )
            case .pastures:
                PastureTileListView(
                    repository: dependencies.pastureRepository,
                    isManaging: $isManagingPastures,
                    filter: pastureFilter
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    switchMode()
                } label: {
                    Label(switchButtonTitle, systemImage: switchButtonSystemImage)
                }
                .accessibilityLabel(switchButtonAccessibilityLabel)
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

    private var switchButtonTitle: String {
        switch mode {
        case .animals:
            return "Pastures"
        case .pastures:
            return "Animals"
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
