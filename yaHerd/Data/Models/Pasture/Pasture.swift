import Foundation
import SwiftData

@Model
final class Pasture {
    @Attribute(.unique) var publicID: UUID
    @Attribute(.unique) var name: String
    @Relationship(deleteRule: .nullify, inverse: \Animal.pasture)
    
    var animals: [Animal] = []
    var acreage: Double?
    var usableAcreage: Double?
    var targetAcresPerHead: Double?
    var lastGrazedDate: Date?
    var group: PastureGroup?

    init(
        publicID: UUID = UUID(),
        name: String,
        acreage: Double? = nil,
        usableAcreage: Double? = nil,
        targetAcresPerHead: Double? = nil
    ) {
        self.publicID = publicID
        self.name = name
        self.acreage = acreage
        self.usableAcreage = usableAcreage
        self.targetAcresPerHead = targetAcresPerHead
    }
}
