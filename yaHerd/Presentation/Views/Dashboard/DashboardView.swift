import SwiftUI

struct DashboardView: View {
    @Environment(\.homeFeatureDependencies) private var homeDependencies
    private var dashboardQueryReader: any DashboardQueryReading { homeDependencies.dashboardQueryReader }
    private var fieldCheckOverviewReader: any FieldCheckOverviewReading { homeDependencies.fieldCheckOverviewReader }

    @State private var viewModel = DashboardViewModel()
    @State private var fieldChecksModel = FieldChecksViewModel()
    @State private var selectedPastureName: String?

    private let configuration = DashboardConfiguration()

    private var presentationData: DashboardPresentationData {
        DashboardPresentationData(
            snapshot: viewModel.snapshot,
            fieldCheckSessions: fieldChecksModel.sessions
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
            async let dashboardObservation: Void = viewModel.observe(
                configuration: configuration,
                using: dashboardQueryReader,
                mutationStream: homeDependencies.mutationStream
            )
            async let fieldCheckObservation: Void = fieldChecksModel.observe(
                using: fieldCheckOverviewReader,
                mutationStream: homeDependencies.mutationStream
            )
            _ = await (dashboardObservation, fieldCheckObservation)
        }
        .alert("Dashboard Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
                fieldChecksModel.errorMessage = nil
            }
        } message: {
            Text(dashboardErrorMessage ?? "Unknown error")
        }
        .profileBodyRecomputation("DashboardView")
    }

    private var dashboardErrorMessage: String? {
        viewModel.errorMessage ?? fieldChecksModel.errorMessage
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { dashboardErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                    fieldChecksModel.errorMessage = nil
                }
            }
        )
    }

    private func loadDashboardData() async {
        async let dashboardLoad: Bool = viewModel.load(
            configuration: configuration,
            using: dashboardQueryReader
        )
        fieldChecksModel.load(using: fieldCheckOverviewReader)
        _ = await dashboardLoad
    }
}
