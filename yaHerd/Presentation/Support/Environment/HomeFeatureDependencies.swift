import Foundation
import SwiftUI

nonisolated struct HomeFeatureDependencies {
    let dashboardReader: any DashboardRecordReading
    let fieldCheckOverviewReader: any FieldCheckOverviewReading
    let dashboardQueryReader: any DashboardQueryReading
    let homeFieldCheckQueryReader: any HomeFieldCheckQueryReading
    let homeWorkingQueryReader: any HomeWorkingQueryReading
    let mutationStream: any ApplicationMutationStreaming

    nonisolated init(
        dashboardReader: any DashboardRecordReading,
        fieldCheckOverviewReader: any FieldCheckOverviewReading,
        dashboardQueryReader: any DashboardQueryReading,
        homeFieldCheckQueryReader: any HomeFieldCheckQueryReading,
        homeWorkingQueryReader: any HomeWorkingQueryReading,
        mutationStream: any ApplicationMutationStreaming
    ) {
        self.dashboardReader = dashboardReader
        self.fieldCheckOverviewReader = fieldCheckOverviewReader
        self.dashboardQueryReader = dashboardQueryReader
        self.homeFieldCheckQueryReader = homeFieldCheckQueryReader
        self.homeWorkingQueryReader = homeWorkingQueryReader
        self.mutationStream = mutationStream
    }

    @MainActor
    static func preview(
        dashboardReader: (any DashboardRecordReading)? = nil,
        fieldCheckOverviewReader: (any FieldCheckOverviewReading)? = nil,
        dashboardQueryReader: (any DashboardQueryReading)? = nil,
        homeFieldCheckQueryReader: (any HomeFieldCheckQueryReading)? = nil,
        homeWorkingQueryReader: (any HomeWorkingQueryReading)? = nil,
        mutationStream: (any ApplicationMutationStreaming)? = nil
    ) -> Self {
        Self(
            dashboardReader: dashboardReader ?? MissingHomeDashboardReader(),
            fieldCheckOverviewReader: fieldCheckOverviewReader ?? MissingHomeFieldCheckOverviewReader(),
            dashboardQueryReader: dashboardQueryReader ?? MissingHomeDashboardQueryReader(),
            homeFieldCheckQueryReader: homeFieldCheckQueryReader ?? MissingHomeFieldCheckQueryReader(),
            homeWorkingQueryReader: homeWorkingQueryReader ?? MissingHomeWorkingQueryReader(),
            mutationStream: mutationStream ?? InactiveApplicationMutationStream()
        )
    }
}

private enum MissingHomeFeatureDependencyError: LocalizedError {
    case dependency(String)

    var errorDescription: String? {
        switch self {
        case .dependency(let name):
            return "\(name) has not been configured."
        }
    }
}

private struct MissingHomeDashboardReader: DashboardRecordReading {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchDashboardRecords() throws -> DashboardRecords {
        throw MissingHomeFeatureDependencyError.dependency("Home dashboard reader")
    }
}

private struct MissingHomeFieldCheckOverviewReader: FieldCheckOverviewReading {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchSessions() throws -> [FieldCheckSessionSummary] {
        throw MissingHomeFeatureDependencyError.dependency("Home field-check overview reader")
    }

    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] {
        throw MissingHomeFeatureDependencyError.dependency("Home field-check overview reader")
    }
}

private struct MissingHomeDashboardQueryReader: DashboardQueryReading {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchDashboardRecords() async throws -> DashboardRecords {
        throw MissingHomeFeatureDependencyError.dependency("Home dashboard query reader")
    }

    func fetchDashboardAnimalRecords(
        kind: DashboardAnimalListKind
    ) async throws -> [DashboardAnimalRecord] {
        throw MissingHomeFeatureDependencyError.dependency("Home dashboard query reader")
    }

    func fetchDashboardPastureRecords() async throws -> [DashboardPastureRecord] {
        throw MissingHomeFeatureDependencyError.dependency("Home dashboard query reader")
    }
}

private struct MissingHomeFieldCheckQueryReader: HomeFieldCheckQueryReading {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchHomeFieldCheckRecords() async throws -> HomeFieldCheckRecords {
        throw MissingHomeFeatureDependencyError.dependency("Home field-check query reader")
    }
}

private struct MissingHomeWorkingQueryReader: HomeWorkingQueryReading {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchHomeTreatmentTemplates(
        limit: Int
    ) async throws -> [WorkingTreatmentTemplateSummary] {
        throw MissingHomeFeatureDependencyError.dependency("Home working query reader")
    }
}

private struct HomeFeatureDependenciesKey: EnvironmentKey {
    static var defaultValue: HomeFeatureDependencies {
        HomeFeatureDependencies(
            dashboardReader: MissingHomeDashboardReader(),
            fieldCheckOverviewReader: MissingHomeFieldCheckOverviewReader(),
            dashboardQueryReader: MissingHomeDashboardQueryReader(),
            homeFieldCheckQueryReader: MissingHomeFieldCheckQueryReader(),
            homeWorkingQueryReader: MissingHomeWorkingQueryReader(),
            mutationStream: InactiveApplicationMutationStream()
        )
    }
}

extension EnvironmentValues {
    var homeFeatureDependencies: HomeFeatureDependencies {
        get { self[HomeFeatureDependenciesKey.self] }
        set { self[HomeFeatureDependenciesKey.self] = newValue }
    }
}
