import Foundation

struct PastureInput: Equatable {
    var name: String
    var acreage: Double?
    var usableAcreage: Double?
    var targetAcresPerHead: Double?

    var normalized: PastureInput {
        PastureInput(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            acreage: acreage,
            usableAcreage: usableAcreage,
            targetAcresPerHead: targetAcresPerHead
        )
    }
}
