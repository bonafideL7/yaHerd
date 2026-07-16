import Foundation
import SwiftUI

nonisolated struct HomeFeatureDependencies {
    let dashboardReader: any DashboardRecordReading
    let fieldCheckOverviewReader: any FieldCheckOverviewReading
    let workingProtocolTemplateReader: any WorkingProtocolTemplateListReader

    nonisolated init(
        dashboardReader: any DashboardRecordReading,
        fieldCheckOverviewReader: any FieldCheckOverviewReading,
        workingProtocolTemplateReader: any WorkingProtocolTemplateListReader
    ) {
        self.dashboardReader = dashboardReader
        self.fieldCheckOverviewReader = fieldCheckOverviewReader
        self.workingProtocolTemplateReader = workingProtocolTemplateReader
    }

    @MainActor
    static func preview(
        dashboardReader: (any DashboardRecordReading)? = nil,
        fieldCheckOverviewReader: (any FieldCheckOverviewReading)? = nil,
        workingProtocolTemplateReader: (any WorkingProtocolTemplateListReader)? = nil
    ) -> Self {
        Self(
            dashboardReader: dashboardReader ?? MissingHomeDashboardReader(),
            fieldCheckOverviewReader: fieldCheckOverviewReader ?? MissingHomeFieldCheckOverviewReader(),
            workingProtocolTemplateReader: workingProtocolTemplateReader ?? MissingHomeWorkingProtocolTemplateReader()
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

private struct HomeFeatureDependenciesKey: EnvironmentKey {
    static let defaultValue = HomeFeatureDependencies(
        dashboardReader: MissingHomeDashboardReader(),
        fieldCheckOverviewReader: MissingHomeFieldCheckOverviewReader(),
        workingProtocolTemplateReader: MissingHomeWorkingProtocolTemplateReader()
    )
}

extension EnvironmentValues {
    var homeFeatureDependencies: HomeFeatureDependencies {
        get { self[HomeFeatureDependenciesKey.self] }
        set { self[HomeFeatureDependenciesKey.self] = newValue }
    }
}
