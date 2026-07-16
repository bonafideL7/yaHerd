import SwiftUI

struct HomeView: View {
    @Environment(\.homeFeatureDependencies) private var homeDependencies
    private var dashboardRecordReader: any DashboardRecordReading { homeDependencies.dashboardReader }
    private var fieldCheckOverviewReader: any FieldCheckOverviewReading { homeDependencies.fieldCheckOverviewReader }
    private var workingProtocolTemplateReader: any WorkingProtocolTemplateListReader { homeDependencies.workingProtocolTemplateReader }
    @EnvironmentObject var tagColorLibrary: TagColorLibraryStore
    @Environment(ApplicationSettings.self) var applicationSettings
    @Environment(AppNavigationState.self) private var navigation

    @State var viewModel = HomeViewModel()

    let refreshToken: Int
    let openAnimalList: (AnimalListLaunchConfiguration) -> Void
    let openPastureList: (PastureListLaunchConfiguration) -> Void
    let openFieldCheckArea: (FieldCheckAreaLaunchConfiguration) -> Void
    let openWorkArea: (WorkAreaLaunchConfiguration) -> Void

    init(
        refreshToken: Int = 0,
        openAnimalList: @escaping (AnimalListLaunchConfiguration) -> Void = { _ in },
        openPastureList: @escaping (PastureListLaunchConfiguration) -> Void = { _ in },
        openFieldCheckArea: @escaping (FieldCheckAreaLaunchConfiguration) -> Void = { _ in },
        openWorkArea: @escaping (WorkAreaLaunchConfiguration) -> Void = { _ in }
    ) {
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
        .task(id: refreshToken) {
            loadHomeDataForCurrentState()
        }
        .onAppear {
            if viewModel.hasLoaded {
                loadHomeData()
            }
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
                navigation.present(.addAnimal)
            } label: {
                Label("Add Animal", systemImage: "tag")
            }

            Button {
                navigation.present(.addPasture)
            } label: {
                Label("Add Pasture", systemImage: "leaf")
            }

            Button {
                navigation.present(.startWorkingSession)
            } label: {
                Label("New Working Session", systemImage: "wrench.and.screwdriver")
            }

            Button {
                navigation.present(.startFieldCheck)
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

    func openFieldChecks(_ mode: FieldChecksViewMode) {
        navigation.openFieldChecks(mode)
    }

    func openWorkingSessionHistory() {
        navigation.openWorkingSessions()
    }

    func presentAddAnimal() {
        navigation.present(.addAnimal)
    }

    func presentAddPasture() {
        navigation.present(.addPasture)
    }

    func presentFieldCheckStart() {
        navigation.present(.startFieldCheck)
    }

    private func makeLoadHomeUseCase() -> LoadHomeUseCase {
        LoadHomeUseCase(
            dashboardRepository: dashboardRecordReader,
            fieldCheckRepository: fieldCheckOverviewReader,
            workingRepository: workingProtocolTemplateReader
        )
    }

    func dismissSetupSuggestion(_ id: HomeSetupSuggestionID) {
        var ids = applicationSettings.homeDismissedSetupSuggestionIDs
        ids.insert(id.rawValue)
        applicationSettings.homeDismissedSetupSuggestionIDs = ids
    }

}
