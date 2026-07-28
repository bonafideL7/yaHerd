import Foundation
import SwiftData

@MainActor
extension SwiftDataWorkingRepository {
    func replacePrimaryTag(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingTagReplacementInput
    ) throws -> WorkingQueueItemEditorSnapshot {
        let normalizedNumber = input.number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNumber.isEmpty else {
            throw WorkingRepositoryError.invalidTagNumber
        }

        let lookup = SwiftDataWorkingLookupStore(context: context)
        let session = try lookup.fetchSession(id: sessionID)
        guard session.status == .active else {
            throw WorkingRepositoryError.sessionAlreadyFinished
        }

        let queueItem = try lookup.fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else {
            throw WorkingRepositoryError.animalNotFound
        }

        let replacementDate = Date.now
        if let primaryTag = animal.primaryTag {
            animal.retireTag(primaryTag, on: replacementDate)
        } else if !animal.tagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let legacyTag = animal.ensurePrimaryTagRecord()
            try ensureUniqueAnimalTagPublicID(legacyTag)
            animal.retireTag(legacyTag, on: replacementDate)
        }

        let replacementTag = animal.addTag(
            number: normalizedNumber,
            colorID: input.colorID,
            isPrimary: true,
            assignedAt: replacementDate
        )
        try ensureUniqueAnimalTagPublicID(replacementTag)

        try PersistenceLog.save(
            context,
            operation: "SwiftDataWorkingRepository.replacePrimaryTag"
        )

        guard let snapshot = try fetchQueueItemEditor(
            sessionID: sessionID,
            queueItemID: queueItemID
        ) else {
            throw WorkingRepositoryError.queueItemNotFound
        }
        return snapshot
    }

    private func ensureUniqueAnimalTagPublicID(_ tag: AnimalTag) throws {
        while try animalTagPublicIDExists(tag.publicID, excluding: tag) {
            tag.publicID = UUID()
        }
    }

    private func animalTagPublicIDExists(_ id: UUID, excluding tag: AnimalTag) throws -> Bool {
        let descriptor = FetchDescriptor<AnimalTag>(
            predicate: #Predicate<AnimalTag> { existing in
                existing.publicID == id
            }
        )
        return try context.fetch(descriptor).contains { $0 !== tag }
    }
}
