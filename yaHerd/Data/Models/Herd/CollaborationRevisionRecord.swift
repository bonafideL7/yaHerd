import Foundation
import SwiftData
import Synchronization

/// Stable bridge entity identifiers used to associate revision metadata with
/// application-managed aggregates without coupling the domain models to Core Data.
enum CollaborationAggregateType: String, CaseIterable, Codable, Sendable {
    case herd = "SharedHerdRecord"
    case tagColorDefinition = "SharedTagColorDefinitionRecord"
    case animalStatusReference = "SharedAnimalStatusReferenceRecord"
    case pastureGroup = "SharedPastureGroupRecord"
    case pasture = "SharedPastureRecord"
    case animal = "SharedAnimalRecord"
    case animalTag = "SharedAnimalTagRecord"
    case movement = "SharedMovementRecord"
    case statusRecord = "SharedStatusRecord"
    case workingProtocolTemplate = "SharedWorkingProtocolTemplateRecord"
    case workingSession = "SharedWorkingSessionRecord"
    case workingQueueItem = "SharedWorkingQueueItemRecord"
    case workingTreatmentRecord = "SharedWorkingTreatmentRecord"
    case healthRecord = "SharedHealthRecord"
    case pregnancyCheck = "SharedPregnancyCheckRecord"
    case fieldCheckSession = "SharedFieldCheckSessionRecord"
    case fieldCheckAnimalCheck = "SharedFieldCheckAnimalCheckRecord"
    case fieldCheckFinding = "SharedFieldCheckFindingRecord"
}

struct CollaborationAggregateKey: Codable, Equatable, Hashable, Sendable {
    let sourceEntityName: String
    let publicID: UUID

    init(type: CollaborationAggregateType, publicID: UUID) {
        self.init(sourceEntityName: type.rawValue, publicID: publicID)
    }

    init(sourceEntityName: String, publicID: UUID) {
        self.sourceEntityName = sourceEntityName
        self.publicID = publicID
    }

    var storageKey: String {
        "\(sourceEntityName)|\(publicID.uuidString.lowercased())"
    }
}

typealias CollaborationFieldSnapshot = [String: HerdSharingBridgeConflictValue]

struct CollaborationRevisionMetadata: Codable, Equatable, Sendable {
    var modifiedAt: Date
    var revision: Int
    var modifiedByParticipantID: String
    var modifiedByDeviceID: String
    var baseRevision: Int
    var baseFieldValues: CollaborationFieldSnapshot
    var currentFieldValues: CollaborationFieldSnapshot
    var isDeleted: Bool

    static func localBootstrap(
        fieldValues: CollaborationFieldSnapshot,
        isDeleted: Bool = false,
        modifiedAt: Date = .now
    ) -> CollaborationRevisionMetadata {
        let identity = CollaborationIdentityProvider.current()
        return CollaborationRevisionMetadata(
            modifiedAt: modifiedAt,
            revision: 1,
            modifiedByParticipantID: identity.participantID,
            modifiedByDeviceID: identity.deviceID,
            baseRevision: 0,
            baseFieldValues: [:],
            currentFieldValues: fieldValues,
            isDeleted: isDeleted
        )
    }

    static func legacySharedBootstrap(
        fieldValues: CollaborationFieldSnapshot,
        isDeleted: Bool,
        modifiedAt: Date
    ) -> CollaborationRevisionMetadata {
        CollaborationRevisionMetadata(
            modifiedAt: modifiedAt,
            revision: 1,
            modifiedByParticipantID: "legacy-unknown",
            modifiedByDeviceID: "legacy-unknown",
            baseRevision: 0,
            baseFieldValues: [:],
            currentFieldValues: fieldValues,
            isDeleted: isDeleted
        )
    }

    func acceptingAsCommonRevision() -> CollaborationRevisionMetadata {
        var accepted = self
        accepted.baseRevision = revision
        accepted.baseFieldValues = currentFieldValues
        return accepted
    }

    static func encodeFieldSnapshot(_ snapshot: CollaborationFieldSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(snapshot)
    }

    static func decodeFieldSnapshot(_ data: Data?) -> CollaborationFieldSnapshot {
        guard let data else { return [:] }
        return (try? JSONDecoder().decode(CollaborationFieldSnapshot.self, from: data)) ?? [:]
    }
}

extension YaHerdSchemaV1 {
    /// Persistent synchronization metadata kept beside each collaboratively mutable aggregate.
    /// The aggregate remains the source of domain values; this record owns revision lineage and
    /// attribution so every mutation path can be stamped at the persistence boundary.
    @Model
    final class CollaborationRevisionRecord {
        var publicID: UUID = UUID()
        var aggregateKey: String = ""
        var sourceEntityName: String = ""
        var aggregatePublicID: UUID = UUID()
        var herdPublicID: UUID?
        var modifiedAt: Date = Date.distantPast
        var revision: Int = 0
        var modifiedByParticipantID: String = ""
        var modifiedByDeviceID: String = ""
        var baseRevision: Int = 0
        var baseFieldValuesData: Data?
        var currentFieldValuesData: Data?
        // `PersistentModel.isDeleted` is SwiftData lifecycle state and cannot store
        // collaboration tombstones. Keep the revision tombstone in its own attribute.
        var deletionTombstone: Bool = false

        /// Source-compatibility alias for existing collaboration code. This is intentionally
        /// computed so SwiftData persists `deletionTombstone` rather than colliding with
        /// `PersistentModel.isDeleted` lifecycle state.
        var isDeleted: Bool {
            get { deletionTombstone }
            set { deletionTombstone = newValue }
        }

        init(
            publicID: UUID = UUID(),
            key: CollaborationAggregateKey,
            herdPublicID: UUID?,
            metadata: CollaborationRevisionMetadata
        ) {
            self.publicID = publicID
            aggregateKey = key.storageKey
            sourceEntityName = key.sourceEntityName
            aggregatePublicID = key.publicID
            self.herdPublicID = herdPublicID
            apply(metadata)
        }

        var key: CollaborationAggregateKey {
            CollaborationAggregateKey(
                sourceEntityName: sourceEntityName,
                publicID: aggregatePublicID
            )
        }

        var metadata: CollaborationRevisionMetadata {
            CollaborationRevisionMetadata(
                modifiedAt: modifiedAt,
                revision: revision,
                modifiedByParticipantID: modifiedByParticipantID,
                modifiedByDeviceID: modifiedByDeviceID,
                baseRevision: baseRevision,
                baseFieldValues: CollaborationRevisionMetadata.decodeFieldSnapshot(baseFieldValuesData),
                currentFieldValues: CollaborationRevisionMetadata.decodeFieldSnapshot(currentFieldValuesData),
                isDeleted: deletionTombstone
            )
        }

        func apply(_ metadata: CollaborationRevisionMetadata) {
            modifiedAt = metadata.modifiedAt
            revision = metadata.revision
            modifiedByParticipantID = metadata.modifiedByParticipantID
            modifiedByDeviceID = metadata.modifiedByDeviceID
            baseRevision = metadata.baseRevision
            baseFieldValuesData = CollaborationRevisionMetadata.encodeFieldSnapshot(metadata.baseFieldValues)
            currentFieldValuesData = CollaborationRevisionMetadata.encodeFieldSnapshot(metadata.currentFieldValues)
            deletionTombstone = metadata.isDeleted
        }
    }
}

protocol CollaborativelyMutableAggregate: AnyObject {
    var collaborationKey: CollaborationAggregateKey { get }
    var collaborationHerdPublicID: UUID? { get }
}

extension Herd: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .herd, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { publicID }
}

extension TagColorDefinition: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .tagColorDefinition, publicID: id)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID }
}

extension AnimalStatusReference: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .animalStatusReference, publicID: id)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID }
}

extension PastureGroup: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .pastureGroup, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID }
}

extension Pasture: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .pasture, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID }
}

extension Animal: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .animal, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID }
}

extension AnimalTag: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .animalTag, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID ?? animal?.herd?.publicID }
}

extension MovementRecord: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .movement, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID ?? animal?.herd?.publicID }
}

extension StatusRecord: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .statusRecord, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID ?? animal?.herd?.publicID }
}

extension WorkingProtocolTemplate: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .workingProtocolTemplate, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID }
}

extension WorkingSession: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .workingSession, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID }
}

extension WorkingQueueItem: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .workingQueueItem, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? {
        herd?.publicID ?? session?.herd?.publicID ?? animal?.herd?.publicID
    }
}

extension WorkingTreatmentRecord: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .workingTreatmentRecord, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? {
        herd?.publicID ?? session?.herd?.publicID ?? animal?.herd?.publicID
    }
}

extension HealthRecord: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .healthRecord, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID ?? animal?.herd?.publicID }
}

extension PregnancyCheck: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .pregnancyCheck, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID ?? animal?.herd?.publicID }
}

extension FieldCheckSession: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .fieldCheckSession, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? { herd?.publicID }
}

extension FieldCheckAnimalCheck: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .fieldCheckAnimalCheck, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? {
        herd?.publicID ?? session?.herd?.publicID ?? animal?.herd?.publicID
    }
}

extension FieldCheckFinding: CollaborativelyMutableAggregate {
    var collaborationKey: CollaborationAggregateKey {
        CollaborationAggregateKey(type: .fieldCheckFinding, publicID: publicID)
    }

    var collaborationHerdPublicID: UUID? {
        herd?.publicID ?? session?.herd?.publicID ?? animal?.herd?.publicID
    }
}

struct CollaborationMutationIdentity: Equatable, Sendable {
    let participantID: String
    let deviceID: String
}

enum CollaborationIdentityProvider {
    private static let participantOverrideKey = "CollaborationParticipantID"
    private static let fallbackParticipantKey = "CollaborationFallbackParticipantID"
    private static let deviceKey = "CollaborationDeviceID"
    private static let cachedIdentity = Mutex<CollaborationMutationIdentity?>(nil)

    static func current() -> CollaborationMutationIdentity {
        cachedIdentity.withLock { cached in
            if let cached { return cached }

            let defaults = UserDefaults.standard
            let participantID = defaults.string(forKey: participantOverrideKey)
                ?? defaults.string(forKey: fallbackParticipantKey)
                ?? UUID().uuidString
            if defaults.string(forKey: fallbackParticipantKey) == nil {
                defaults.set(participantID, forKey: fallbackParticipantKey)
            }

            let deviceID = defaults.string(forKey: deviceKey) ?? UUID().uuidString
            if defaults.string(forKey: deviceKey) == nil {
                defaults.set(deviceID, forKey: deviceKey)
            }

            let identity = CollaborationMutationIdentity(
                participantID: participantID,
                deviceID: deviceID
            )
            cached = identity
            return identity
        }
    }

    /// Allows the CloudKit adapter to replace the installation fallback with a
    /// stable participant identifier when one is available.
    static func registerParticipantID(_ participantID: String) {
        let normalized = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        UserDefaults.standard.set(normalized, forKey: participantOverrideKey)
        cachedIdentity.withLock { $0 = nil }
    }

    static func resetForTesting() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: participantOverrideKey)
        defaults.removeObject(forKey: fallbackParticipantKey)
        defaults.removeObject(forKey: deviceKey)
        cachedIdentity.withLock { $0 = nil }
    }
}
