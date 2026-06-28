import Foundation
import SwiftUI

enum MissingReadModelDependencyError: LocalizedError {
    case dashboardRecordReader
    case fieldCheckReader
    case workingProtocolTemplateReader

    var errorDescription: String? {
        switch self {
        case .dashboardRecordReader:
            return "Dashboard record reader has not been configured."
        case .fieldCheckReader:
            return "Field check reader has not been configured."
        case .workingProtocolTemplateReader:
            return "Working protocol template reader has not been configured."
        }
    }
}

private struct MissingDashboardRecordReader: DashboardRecordReading {
    func fetchDashboardRecords() throws -> DashboardRecords {
        throw MissingReadModelDependencyError.dashboardRecordReader
    }
}

private struct MissingFieldCheckOverviewReader: FieldCheckOverviewReading {
    func fetchSessions() throws -> [FieldCheckSessionSummary] {
        throw MissingReadModelDependencyError.fieldCheckReader
    }

    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] {
        throw MissingReadModelDependencyError.fieldCheckReader
    }
}

private struct MissingWorkingProtocolTemplateReader: WorkingProtocolTemplateListReader {
    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary] {
        throw MissingReadModelDependencyError.workingProtocolTemplateReader
    }
}

private struct DashboardRecordReaderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any DashboardRecordReading = MissingDashboardRecordReader()
}

private struct FieldCheckOverviewReaderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any FieldCheckOverviewReading = MissingFieldCheckOverviewReader()
}

private struct WorkingProtocolTemplateReaderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any WorkingProtocolTemplateListReader = MissingWorkingProtocolTemplateReader()
}

extension EnvironmentValues {
    var dashboardRecordReader: any DashboardRecordReading {
        get { self[DashboardRecordReaderEnvironmentKey.self] }
        set { self[DashboardRecordReaderEnvironmentKey.self] = newValue }
    }

    var fieldCheckOverviewReader: any FieldCheckOverviewReading {
        get { self[FieldCheckOverviewReaderEnvironmentKey.self] }
        set { self[FieldCheckOverviewReaderEnvironmentKey.self] = newValue }
    }

    var workingProtocolTemplateReader: any WorkingProtocolTemplateListReader {
        get { self[WorkingProtocolTemplateReaderEnvironmentKey.self] }
        set { self[WorkingProtocolTemplateReaderEnvironmentKey.self] = newValue }
    }
}
