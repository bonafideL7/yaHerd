import Foundation
import SwiftUI

nonisolated struct HomeFeatureDependencies {
    let dashboardReader: any DashboardRecordReading
    let fieldCheckOverviewReader: any FieldCheckOverviewReading
    let workingTreatmentTemplateReader: any WorkingTreatmentTemplateListReader
    let mutationStream: any ApplicationMutationStreaming

    nonisolated init(
        dashboardReader: any DashboardRecordReading,
        fieldCheckOverviewReader: any FieldCheckOverviewReading,
        workingTreatmentTemplateReader: any WorkingTreatmentTemplateListReader,
        mutationStream: any ApplicationMutationStreaming
    ) {
        self.dashboardReader = dashboardReader
        self.fieldCheckOverviewReader = fieldCheckOverviewReader
        self.workingTreatmentTemplateReader = workingTreatmentTemplateReader
        self.mutationStream = mutationStream
    }

    @MainActor
    static func preview(
        dashboardReader: (any DashboardRecordReading)? = nil,
        fieldCheckOverviewReader: (any FieldCheckOverviewReading)? = nil,
        workingTreatmentTemplateReader: (any WorkingTreatmentTemplateListReader)? = nil,
        mutationStream: (any ApplicationMutationStreaming)? = nil
    ) -> Self {
        Self(
            dashboardReader: dashboardReader ?? MissingHomeDashboardReader(),
            fieldCheckOverviewReader: fieldCheckOverviewReader ?? MissingHomeFieldCheckOverviewReader(),
            workingTreatmentTemplateReader: workingTreatmentTemplateReader ?? MissingHomeWorkingTreatmentTemplateReader(),
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

private struct MissingHomeWorkingTreatmentTemplateReader: WorkingTreatmentTemplateListReader {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchTemplates() throws -> [WorkingTreatmentTemplateSummary] {
        throw MissingHomeFeatureDependencyError.dependency("Home working treatment template reader")
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
            dashboardReader: MissingHomeDashboardReader(),
            fieldCheckOverviewReader: MissingHomeFieldCheckOverviewReader(),
            workingTreatmentTemplateReader: MissingHomeWorkingTreatmentTemplateReader(),
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
