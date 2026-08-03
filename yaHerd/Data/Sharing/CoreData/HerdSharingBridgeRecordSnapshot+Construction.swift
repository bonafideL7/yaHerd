import Foundation

extension HerdSharingBridgeRecordSnapshot {
    init(
        entityName: String,
        publicID: String,
        sourceObjectURI: String,
        attributes: [String: HerdSharingBridgeAttributeValue]
    ) {
        self.entityName = entityName
        self.publicID = publicID
        self.sourceObjectURI = sourceObjectURI
        self.attributes = attributes
    }
}
