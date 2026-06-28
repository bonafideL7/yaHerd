import Foundation

enum WorkingGeneratedHealthRecord: String, CaseIterable, Hashable {
    case castration = "Castration"
    case observation = "Observation"

    var treatmentName: String { rawValue }
}
