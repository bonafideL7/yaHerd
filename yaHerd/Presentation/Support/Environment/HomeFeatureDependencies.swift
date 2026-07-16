import Foundation
import SwiftUI

nonisolated struct HomeFeatureDependencies {
    let dashboardReader: any DashboardRecordReading
    let fieldCheckOverviewReader: any FieldCheckOverviewReading
    let workingProtocolTemplateReader: any WorkingProtocolTemplateListReader
    let mutationStream: any ApplicationMutationStreaming

    nonisolated init(
        dashboardReader: any DashboardRecordReading,
        fieldCheckOverviewReader: any FieldCheckOverviewReading,
        workingProtocolTemplateReader: any WorkingProtocolTemplateListReader,
        mutationStream: any ApplicationMutationStreaming
    ) {
        self.dashboardReader = dashboardReader
        self.fieldCheckOverviewReader = fieldCheckOverviewReader
        self.workingProtocolTemplateReader = workingProtocolTemplateReader
        self.mutationStream = mutationStream
    }

    @MainActor
    static func preview(
        dashboardReader: (any DashboardRecordReading)? = nil,
        fieldCheckOverviewReader: (any FieldCheckOverviewReading)? = nil,
        workingProtocolTemplateReader: (any WorkingProtocolTemplateListReader)? = nil,
        mutationStream: (any ApplicationMutationStreaming)? = nil
    ) -> Self {
        Self(
            dashboardReader: dashboardReader ?? MissingHomeDashboardReader(),
            fieldCheckOverviewReader: fieldCheckOverviewReader ?? MissingHomeFieldCheckOverviewReader(),
            workingProtocolTemplateReader: workingProtocolTemplateReader ?? MissingHomeWorkingProtocolTemplateReader(),
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

private struct MissingHomeWorkingProtocolTemplateReader: WorkingProtocolTemplateListReader {
    nonisolated init(environmentFallback _: Void = ()) {}

    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary] {
        throw MissingHomeFeatureDependencyError.dependency("Home working protocol template reader")
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
            workingProtocolTemplateReader: MissingHomeWorkingProtocolTemplateReader(),
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
