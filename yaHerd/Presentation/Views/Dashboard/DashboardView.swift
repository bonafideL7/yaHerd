import SwiftUI

struct DashboardView: View {
    @Environment(\.homeFeatureDependencies) private var homeDependencies
    private var dashboardReadModel: any DashboardReadModel { homeDependencies.dashboardReadModel }
    private var fieldCheckReadModel: any HomeFieldCheckReadModel { homeDependencies.fieldCheckReadModel }

    @State private var viewModel = DashboardViewModel()
    @State private var fieldCheckSessions: [FieldCheckSessionSummary] = []
    @State private var fieldCheckErrorMessage: String?
    @State private var selectedPastureName: String?

    private let configuration = DashboardConfiguration()

    private var presentationData: DashboardPresentationData {
        DashboardPresentationData(
            snapshot: viewModel.snapshot,
            fieldCheckSessions: fieldCheckSessions
        )
    }

    var body: some View {
        ScrollView {
            DashboardChartsContent(
                data: presentationData,
                isLoaded: viewModel.snapshot != nil,
                selectedPastureName: $selectedPastureName
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .refreshable {
            await loadDashboardData()
        }
        .task {
            await loadDashboardDataIfNeeded()
        }
        .alert("Dashboard Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
                fieldCheckErrorMessage = nil
            }
        } message: {
            Text(dashboardErrorMessage ?? "Unknown error")
        }
        .profileBodyRecomputation("DashboardView")
    }

    private var dashboardErrorMessage: String? {
        viewModel.errorMessage ?? fieldCheckErrorMessage
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { dashboardErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                    fieldCheckErrorMessage = nil
                }
            }
        )
    }

    private func loadDashboardDataIfNeeded() async {
        async let dashboardLoad: Void = viewModel.loadIfNeeded(
            configuration: configuration,
            using: dashboardReadModel
        )
        async let fieldCheckLoad: Void = loadFieldChecksIfNeeded()
        _ = await (dashboardLoad, fieldCheckLoad)
    }

    private func loadDashboardData() async {
        async let dashboardLoad: Void = viewModel.load(
            configuration: configuration,
            using: dashboardReadModel
        )
        async let fieldCheckLoad: Void = loadFieldChecks()
        _ = await (dashboardLoad, fieldCheckLoad)
    }

    private func loadFieldChecksIfNeeded() async {
        guard fieldCheckSessions.isEmpty else { return }
        await loadFieldChecks()
    }

    private func loadFieldChecks() async {
        do {
            fieldCheckSessions = try await fieldCheckReadModel.fetchRecentSessions(limit: 250)
            fieldCheckErrorMessage = nil
        } catch {
            fieldCheckErrorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
