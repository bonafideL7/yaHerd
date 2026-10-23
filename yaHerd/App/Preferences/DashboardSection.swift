nonisolated enum DashboardSection: String, CaseIterable, Identifiable, Sendable {
    case animalTypeMix
    case sexMix
    case pastureAssignment
    case herdLifecycle
    case pastureUtilization
    case calvingBySeason
    case medicalRecordsByMonth
    case pinkEyeTrend
    case offspringByDam
    case soldAndDeceasedTrend
    case fieldCheckHeadCountTrend
    case fieldCheckIssuesOverTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .animalTypeMix: "Animal Type Mix"
        case .sexMix: "Sex Mix"
        case .pastureAssignment: "Pasture Assignment"
        case .herdLifecycle: "Herd Lifecycle"
        case .pastureUtilization: "Pasture Utilization"
        case .calvingBySeason: "Calving by Season"
        case .medicalRecordsByMonth: "Medical Records by Month"
        case .pinkEyeTrend: "Pink Eye Trend"
        case .offspringByDam: "Offspring by Dam"
        case .soldAndDeceasedTrend: "Sold and Deceased Trend"
        case .fieldCheckHeadCountTrend: "Field Check Head Count Trend"
        case .fieldCheckIssuesOverTime: "Field Check Issues Over Time"
        }
    }
}
