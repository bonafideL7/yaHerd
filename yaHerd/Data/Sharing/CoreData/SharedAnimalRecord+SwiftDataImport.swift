//
//  SharedAnimalRecord+SwiftDataImport.swift
//  yaHerd
//

import Foundation

extension SharedAnimalRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }

    var parsedTagColorID: UUID? {
        guard let tagColorID else { return nil }
        return UUID(uuidString: tagColorID)
    }

    var parsedStatusReferenceID: UUID? {
        guard let statusReferenceID else { return nil }
        return UUID(uuidString: statusReferenceID)
    }

    var parsedPasturePublicID: UUID? {
        guard let pasturePublicID else { return nil }
        return UUID(uuidString: pasturePublicID)
    }

    var parsedSireAnimalPublicID: UUID? {
        guard let sireAnimalPublicID else { return nil }
        return UUID(uuidString: sireAnimalPublicID)
    }

    var parsedDamAnimalPublicID: UUID? {
        guard let damAnimalPublicID else { return nil }
        return UUID(uuidString: damAnimalPublicID)
    }

    var parsedSex: Sex {
        guard let sexRawValue else { return .unknown }
        return Sex(rawValue: sexRawValue) ?? .unknown
    }

    var parsedStatus: AnimalStatus {
        guard let statusRawValue else { return .active }
        return AnimalStatus(rawValue: statusRawValue) ?? .active
    }

    var parsedLocation: AnimalLocation {
        guard let locationRawValue else { return .pasture }
        return AnimalLocation(rawValue: locationRawValue) ?? .pasture
    }

    var parsedDistinguishingFeatures: [DistinguishingFeature] {
        guard let distinguishingFeaturesJSON else { return [] }
        do {
            return try JSONDecoder().decode([DistinguishingFeature].self, from: distinguishingFeaturesJSON)
        } catch {
            PersistenceLog.decodeFailure("SharedAnimalRecord.parsedDistinguishingFeatures.decode", error: error)
            return []
        }
    }
}
