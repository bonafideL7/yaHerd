import Foundation

// SwiftData V1 persists treatment-plan items under the original protocol vocabulary.
// Keep this storage alias until the Core Data cutover removes the legacy model names.
typealias WorkingProtocolItem = WorkingTreatmentPlanItem

// SwiftDataWorkingRepository still exposes these two legacy result names internally.
// Domain and Presentation APIs use the treatment-template names directly.
typealias WorkingProtocolTemplateSummary = WorkingTreatmentTemplateSummary
typealias WorkingProtocolTemplateDetailSnapshot = WorkingTreatmentTemplateDetailSnapshot
