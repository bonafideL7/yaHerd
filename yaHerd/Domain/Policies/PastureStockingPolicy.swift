import Foundation

enum PastureStockingPolicy {
    static let minimumAcreageForStockingFields = 1.0
    static let underutilizedThreshold = 0.40
    static let rotationReadyUtilizationThreshold = 0.80
    static let utilizationWarningThreshold = 0.75
    static let utilizationDangerThreshold = 0.90

    static func shouldUseStockingFields(acreage: Double?) -> Bool {
        guard let acreage else { return false }
        return acreage > minimumAcreageForStockingFields
    }

    static func isRotationReady(
        isRestedForRotation: Bool,
        isOverCapacity: Bool,
        utilizationPercent: Double?,
        activeAnimalCount: Int
    ) -> Bool {
        guard isRestedForRotation, !isOverCapacity else { return false }
        guard let utilizationPercent else { return activeAnimalCount == 0 }
        return utilizationPercent < rotationReadyUtilizationThreshold
    }

    static func status(utilizationPercent: Double?, isOverCapacity: Bool) -> PastureUtilizationStatus {
        if isOverCapacity {
            return .overCapacity
        }

        guard let utilizationPercent else {
            return .missingData
        }

        if utilizationPercent < underutilizedThreshold {
            return .underutilized
        }

        if utilizationPercent >= utilizationDangerThreshold {
            return .danger
        }

        if utilizationPercent >= utilizationWarningThreshold {
            return .warning
        }

        return .normal
    }
}
