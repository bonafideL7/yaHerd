import Foundation
import SwiftData

@Model
final class Pasture {
    var publicID: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    @Relationship(deleteRule: .nullify, inverse: \Animal.pasture)
    var animalStorage: [Animal]?

    var animals: [Animal] {
        get { animalStorage ?? [] }
        set { animalStorage = newValue }
    }
    var acreage: Double?
    var usableAcreage: Double?
    var targetAcresPerHead: Double?
    var lastGrazedDate: Date?

    @Relationship(deleteRule: .nullify)
    var group: PastureGroup?

    @Relationship(deleteRule: .nullify, inverse: \WorkingSession.sourcePasture)
    var sourceWorkingSessionStorage: [WorkingSession]?

    @Relationship(deleteRule: .nullify, inverse: \WorkingQueueItem.collectedFromPasture)
    var collectedWorkingQueueItemStorage: [WorkingQueueItem]?

    @Relationship(deleteRule: .nullify, inverse: \WorkingQueueItem.destinationPasture)
    var destinationWorkingQueueItemStorage: [WorkingQueueItem]?

    @Relationship(deleteRule: .nullify, inverse: \FieldCheckSession.pasture)
    var fieldCheckSessionStorage: [FieldCheckSession]?

    init(
        publicID: UUID = UUID(),
        name: String,
        acreage: Double? = nil,
        usableAcreage: Double? = nil,
        targetAcresPerHead: Double? = nil,
        sortOrder: Int = 0
    ) {
        self.publicID = publicID
        self.name = name
        self.acreage = acreage
        self.usableAcreage = usableAcreage
        self.targetAcresPerHead = targetAcresPerHead
        self.sortOrder = sortOrder
    }
}
