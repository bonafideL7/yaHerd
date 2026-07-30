import Foundation
import SwiftUI

nonisolated struct HomeFeatureDependencies {
    let dashboardReadModel: any DashboardReadModel
    let fieldCheckReadModel: any HomeFieldCheckReadModel
    let workingReadModel: any HomeWorkingReadModel
    let mutationStream: any ApplicationMutationStreaming

    nonisolated init(
        dashboardReadModel: any DashboardReadModel,
        fieldCheckReadModel: any HomeFieldCheckReadModel,
        workingReadModel: any HomeWorkingReadModel,
        mutationStream: any ApplicationMutationStreaming
    ) {
        self.dashboardReadModel = dashboardReadModel
        self.fieldCheckReadModel = fieldCheckReadModel
        self.workingReadModel = workingReadModel
        self.mutationStream = mutationStream
    }

    @MainActor
    static func preview(
        dashboardReadModel: (any DashboardReadModel)? = nil,
        fieldCheckReadModel: (any HomeFieldCheckReadModel)? = nil,
        workingReadModel: (any HomeWorkingReadModel)? = nil,
        mutationStream: (any ApplicationMutationStreaming)? = nil
    ) -> Self {
        Self(
            dashboardReadModel: dashboardReadModel ?? MissingHomeDashboardReadModel(),
            fieldCheckReadModel: fieldCheckReadModel ?? MissingHomeFieldCheckReadModel(),
            workingReadModel: workingReadModel ?? MissingHomeWorkingReadModel(),
            mutationStream: mutationStream ?? MissingHomeMutationStream()
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

private struct MissingHomeDashboardReadModel: DashboardReadModel {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchDashboardRecords(pageSize: Int) async throws -> DashboardRecords {
        throw MissingHomeFeatureDependencyError.dependency("Home dashboard read model")
    }

    func fetchDashboardSnapshot(
        configuration: DashboardConfiguration,
        now: Date,
        pageSize: Int
    ) async throws -> DashboardSnapshot {
        throw MissingHomeFeatureDependencyError.dependency("Home dashboard read model")
    }
}

private struct MissingHomeFieldCheckReadModel: HomeFieldCheckReadModel {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchRecentSessions(limit: Int) async throws -> [FieldCheckSessionSummary] {
        throw MissingHomeFeatureDependencyError.dependency("Home field-check read model")
    }

    func fetchOpenFindings(limit: Int) async throws -> [FieldCheckFindingSnapshot] {
        throw MissingHomeFeatureDependencyError.dependency("Home field-check read model")
    }
}

private struct MissingHomeWorkingReadModel: HomeWorkingReadModel {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchTreatmentTemplates(limit: Int) async throws -> [WorkingTreatmentTemplateSummary] {
        throw MissingHomeFeatureDependencyError.dependency("Home working read model")
    }
}

private struct MissingHomeMutationStream: ApplicationMutationStreaming {
    nonisolated init(environmentFallback _: Void = ()) {}

    var currentSequence: UInt64 { 0 }

    func events(after sequence: UInt64) -> AsyncStream<ApplicationMutationEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private struct HomeFeatureDependenciesKey: EnvironmentKey {
    static var defaultValue: HomeFeatureDependencies {
        HomeFeatureDependencies(
            dashboardReadModel: MissingHomeDashboardReadModel(),
            fieldCheckReadModel: MissingHomeFieldCheckReadModel(),
            workingReadModel: MissingHomeWorkingReadModel(),
            mutationStream: MissingHomeMutationStream()
        )
    }
}

extension EnvironmentValues {
    var homeFeatureDependencies: HomeFeatureDependencies {
        get { self[HomeFeatureDependenciesKey.self] }
        set { self[HomeFeatureDependenciesKey.self] = newValue }
    }
}
