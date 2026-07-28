import CoreData

extension HerdSharingCoreDataModelFactory {
    /// Current unreleased V1 bridge model. The bridge is updated in lockstep with
    /// `YaHerdSchemaV1`; this is not a second application schema version.
    static func makeCurrentModel() -> NSManagedObjectModel {
        let model = makeModel()
        guard let entity = model.entitiesByName[SharedWorkingTreatmentRecord.entityName] else {
            return model
        }

        // `quantity` was the pre-release placeholder. V1 stores a structured dose.
        entity.properties.removeAll { $0.name == "quantity" }
        appendAttributeIfMissing(
            name: "treatmentItemID",
            type: .stringAttributeType,
            to: entity
        )
        appendAttributeIfMissing(
            name: "doseAmount",
            type: .doubleAttributeType,
            to: entity
        )
        appendAttributeIfMissing(
            name: "doseUnitRawValue",
            type: .stringAttributeType,
            to: entity
        )
        appendAttributeIfMissing(
            name: "administrationRouteRawValue",
            type: .stringAttributeType,
            to: entity
        )
        return model
    }

    private static func appendAttributeIfMissing(
        name: String,
        type: NSAttributeType,
        to entity: NSEntityDescription
    ) {
        guard entity.propertiesByName[name] == nil else { return }
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        entity.properties.append(attribute)
    }
}
