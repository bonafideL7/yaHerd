import Foundation

enum PastureUtilizationStatus: Hashable {
    case missingData
    case underutilized
    case normal
    case warning
    case danger
    case overCapacity
}
