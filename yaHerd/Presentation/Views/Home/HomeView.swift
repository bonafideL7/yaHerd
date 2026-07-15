import SwiftUI

struct HomeView: View {
    @Environment(\.dashboardRecordReader) private var dashboardRecordReader
    @Environment(\.fieldCheckOverviewReader) private var fieldCheckOverviewReader
    @Environment(\.workingProtocolTemplateReader) private var workingProtocolTemplateReader
    @EnvironmentObject var tagColorLibrary: TagColorLibraryStore

    @AppStorage("isDashboardEnabled") var isDashboardEnabled = false
    @AppStorage("syncMode") var syncModeRawValue = SyncMode.localOnly.rawValue
    @AppStorage("homeDismissedSetupSuggestionIDs") var dismissedSetupSuggestionIDsRaw = ""
    @AppStorage("homeSetupSuggestionsExpanded") var isSetupSuggestionsExpanded = true

    @State var viewModel = HomeViewModel()
    @Binding var isPresentingAddAnimal: Bool
    @Binding var isPresentingAddPasture: Bool
    @Binding var isPresentingNewWorkingSession: Bool
    @Binding var isStartingFieldCheck: Bool

    let refreshToken: Int
    let openAnimalList: (AnimalListLaunchConfiguration) -> Void
    let openPastureList: (PastureListLaunchConfiguration) -> Void
    let openFieldCheckArea: (FieldCheckAreaLaunchConfiguration) -> Void
    let openWorkArea: (WorkAreaLaunchConfiguration) -> Void

    init(
        isPresentingAddAnimal: Binding<Bool>,
        isPresentingAddPasture: Binding<Bool>,
        isPresentingNewWorkingSession: Binding<Bool>,
        isStartingFieldCheck: Binding<Bool>,
        refreshToken: Int = 0,
        openAnimalList: @escaping (AnimalListLaunchConfiguration) -> Void = { _ in },
        openPastureList: @escaping (PastureListLaunchConfiguration) -> Void = { _ in },
        openFieldCheckArea: @escaping (FieldCheckAreaLaunchConfiguration) -> Void = { _ in },
        openWorkArea: @escaping (WorkAreaLaunchConfiguration) -> Void = { _ in }
    ) {
        self._isPresentingAddAnimal = isPresentingAddAnimal
        self._isPresentingAddPasture = isPresentingAddPasture
        self._isPresentingNewWorkingSession = isPresentingNewWorkingSession
        self._isStartingFieldCheck = isStartingFieldCheck
        self.refreshToken = refreshToken
        self.openAnimalList = openAnimalList
        self.openPastureList = openPastureList
        self.openFieldCheckArea = openFieldCheckArea
        self.openWorkArea = openWorkArea
    }

    let configuration = DashboardConfiguration()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                setupSuggestionsSection
                homeSummaryCardsSection
                alertsSection
                fieldWorkSection
                workPenSection
                pastureOperationsSection
                recordsCleanupSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            addMenu
                .padding(.trailing, 24)
                .padding(.bottom, 24)
        }
        .navigationDestination(isPresented: $isStartingFieldCheck) {
            HomePastureCheckStartListView(pastures: pastureCheckStartPastures) { sessionID in
                isStartingFieldCheck = false
                openFieldCheckArea(.session(FieldCheckSessionLaunchConfiguration(sessionID: sessionID)))
            }
        }
        .navigationDestination(isPresented: $isPresentingNewWorkingSession) {
            WorkingSessionPastureStartListView { sessionID in
                isPresentingNewWorkingSession = false
                openWorkArea(.session(sessionID))
            }
        }
        .task(id: refreshToken) {
            loadHomeDataForCurrentState()
        }
        .onAppear {
            if viewModel.hasLoaded {
                loadHomeData()
            }
        }
        .onChange(of: isPresentingAddAnimal) { _, isPresented in
            if !isPresented { loadHomeData() }
        }
        .onChange(of: isPresentingAddPasture) { _, isPresented in
            if !isPresented { loadHomeData() }
        }
        .onChange(of: isPresentingNewWorkingSession) { _, isPresented in
            if !isPresented { loadHomeData() }
        }
        .sheet(isPresented: $isPresentingAddAnimal) {
            AddAnimalView()
        }
        .sheet(isPresented: $isPresentingAddPasture) {
            AddPastureView()
        }
        .alert("Home Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(homeErrorMessage ?? "Unknown error")
        }
        .profileBodyRecomputation("HomeView")
    }

    var addMenu: some View {
        Menu {
            Button {
                isPresentingAddAnimal = true
            } label: {
                Label("Add Animal", systemImage: "tag")
            }

            Button {
                isPresentingAddPasture = true
            } label: {
                Label("Add Pasture", systemImage: "leaf")
            }

            Button {
                isPresentingNewWorkingSession = true
            } label: {
                Label("New Working Session", systemImage: "wrench.and.screwdriver")
            }

            Button {
                isStartingFieldCheck = true
            } label: {
                Label("Start Pasture Check", systemImage: "checklist")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        }
        .accessibilityLabel("Add")
        .disabledWhenDataReadOnly()
    }

    var homeErrorMessage: String? {
        viewModel.errorMessage
    }

    var errorBinding: Binding<Bool> {
        Binding(
            get: { homeErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    func loadHomeDataForCurrentState() {
        if viewModel.hasLoaded {
            loadHomeData()
        } else {
            loadHomeDataIfNeeded()
        }
    }

    func loadHomeDataIfNeeded() {
        viewModel.loadIfNeeded(
            configuration: configuration,
            useCase: makeLoadHomeUseCase()
        )
    }

    func loadHomeData() {
        viewModel.load(
            configuration: configuration,
            useCase: makeLoadHomeUseCase()
        )
    }

    private func makeLoadHomeUseCase() -> LoadHomeUseCase {
        LoadHomeUseCase(
            dashboardRepository: dashboardRecordReader,
            fieldCheckRepository: fieldCheckOverviewReader,
            workingRepository: workingProtocolTemplateReader
        )
    }

    func dismissSetupSuggestion(_ id: HomeSetupSuggestionID) {
        var ids = dismissedSetupSuggestionIDs
        ids.insert(id.rawValue)
        dismissedSetupSuggestionIDsRaw = ids.sorted().joined(separator: ",")
    }

}
