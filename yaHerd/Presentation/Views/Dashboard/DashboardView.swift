import SwiftUI

struct DashboardView: View {
    @Environment(\.dashboardRecordReader) private var dashboardRecordReader
    @Environment(\.fieldCheckOverviewReader) private var fieldCheckOverviewReader

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
            loadDashboardData()
        }
        .task {
            loadDashboardDataIfNeeded()
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

    private func loadDashboardDataIfNeeded() {
        viewModel.loadIfNeeded(configuration: configuration, using: dashboardRecordReader)
        fieldChecksModel.loadIfNeeded(using: fieldCheckOverviewReader)
    }

    private func loadDashboardData() {
        viewModel.load(configuration: configuration, using: dashboardRecordReader)
        fieldChecksModel.load(using: fieldCheckOverviewReader)
    }
}
