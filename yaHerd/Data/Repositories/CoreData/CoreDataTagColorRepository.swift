@preconcurrency import CoreData
import Foundation

@MainActor
final class CoreDataTagColorRepository: TagColorRepository {
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    private let lookup: CoreDataLookup

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        lookup: CoreDataLookup
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.lookup = lookup
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup
        )
    }

    func fetchColors() throws -> [TagColorSnapshot] {
        let herdID = try currentHerdID()
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            let persisted = try fetchPersistedColors(for: herd, in: context)
            var snapshotsByID = Dictionary(
                uniqueKeysWithValues: TagColorDefaults.seedDefaultColors().map { ($0.id, $0) }
            )

            // Application UUID is authoritative. A materialized built-in may legitimately have an
            // edited display name, so overlaying by UUID prevents its virtual definition from
            // appearing as a second SwiftUI identity.
            let builtInIDs = Set(TagColorDefaults.seedDefaultColors().map(\.id))
            for color in persisted {
                if !color.isHidden {
                    snapshotsByID[color.id] = color.toSnapshot()
                } else if builtInIDs.contains(color.id),
                          var virtualBuiltIn = snapshotsByID[color.id] {
                    // A referenced deleted built-in keeps its historical display fields hidden for
                    // UUID lookup, while sort/default metadata continues to drive the canonical
                    // virtual built-in shown in settings.
                    virtualBuiltIn.sortOrder = Int(color.sortOrder)
                    virtualBuiltIn.isDefault = color.isDefault
                    snapshotsByID[color.id] = virtualBuiltIn
                }
            }

            if let selectedDefaultID = persisted
                .filter({ $0.isDefault })
                .sorted(by: defaultSort)
                .first?.id {
                for id in Array(snapshotsByID.keys) {
                    guard var snapshot = snapshotsByID[id] else { continue }
                    snapshot.isDefault = snapshot.id == selectedDefaultID
                    snapshotsByID[id] = snapshot
                }
            }

            var result = snapshotsByID.values.sorted(by: snapshotSort)
            if !result.contains(where: \.isDefault),
               let whiteIndex = result.firstIndex(where: { $0.id == TagColorDefaults.whiteID }) {
                result[whiteIndex].isDefault = true
            }
            return result
        }
    }

    func fetchColor(id: UUID) throws -> TagColorSnapshot? {
        let herdID = try currentHerdID()
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard try lookup.herd(id: herdID, in: context) != nil else {
                throw HerdRepositoryError.missingHerd
            }

            if let persisted = try lookup.herdOwned(
                CDTagColorDefinition.self,
                id: id,
                herdID: herdID,
                in: context
            ) {
                return persisted.toSnapshot()
            }

            return TagColorDefaults.seedDefaultColors().first { $0.id == id }
        }
    }

    func upsert(_ color: TagColorSnapshot) throws {
        let cleanedName = TagColorLibraryRules.normalizedDisplayName(color.name)
        guard !cleanedName.isEmpty else { return }

        let herdID = try currentHerdID()
        try performWrite { context, herd in
            let cleanedPrefix = TagColorLibraryRules.normalizedPrefix(
                color.prefix,
                fallbackName: cleanedName
            )
            let persisted = try fetchPersistedColors(for: herd, in: context)
            let nameKey = TagColorLibraryRules.normalizedNameKey(cleanedName)
            let builtIns = TagColorDefaults.seedDefaultColors()
            let builtInByID = builtIns.first { $0.id == color.id }
            let builtInByName = builtIns.first {
                TagColorLibraryRules.normalizedNameKey($0.name) == nameKey
            }
            if let builtInByID,
               let builtInByName,
               builtInByID.id != builtInByName.id {
                // Both UUIDs are stable application identities. A rename may edit a built-in's
                // display definition, but it must never repurpose or absorb another built-in.
                return
            }

            let builtIn = builtInByID ?? builtInByName

            let existingByID = persisted.first { $0.id == color.id }
            let existingByName = persisted
                .filter { $0.id != color.id }
                .sorted(by: persistedSort)
                .first {
                    TagColorLibraryRules.normalizedNameKey($0.name) == nameKey
                }

            let canonicalID = builtIn?.id ?? existingByName?.id ?? color.id
            let canonical: CDTagColorDefinition

            if let existing = persisted.first(where: { $0.id == canonicalID }) {
                canonical = existing
            } else {
                canonical = CDTagColorDefinition(context: context)
                canonical.id = canonicalID
                canonical.name = builtIn?.name ?? cleanedName
                canonical.prefix = builtIn?.prefix ?? cleanedPrefix
                canonical.red = builtIn?.rgba.r ?? color.rgba.r
                canonical.green = builtIn?.rgba.g ?? color.rgba.g
                canonical.blue = builtIn?.rgba.b ?? color.rgba.b
                canonical.alpha = builtIn?.rgba.a ?? color.rgba.a
                canonical.sortOrder = Int64(builtIn?.sortOrder ?? persisted.filter { !$0.isHidden }.count)
                canonical.isHidden = false
                canonical.isDefault = builtIn?.isDefault ?? false
                canonical.createdAt = builtIn?.createdAt ?? color.createdAt
                canonical.updatedAt = builtIn?.updatedAt ?? color.updatedAt
                canonical.herd = herd
            }

            let wasDefault = canonical.isDefault || existingByID?.isDefault == true
            canonical.name = cleanedName
            canonical.prefix = cleanedPrefix
            canonical.red = color.rgba.r
            canonical.green = color.rgba.g
            canonical.blue = color.rgba.b
            canonical.alpha = color.rgba.a
            canonical.isHidden = false
            canonical.isDefault = color.isDefault || wasDefault
            canonical.updatedAt = max(canonical.updatedAt, color.updatedAt)

            let duplicateIDs = Set(
                [existingByID, existingByName]
                    .compactMap { $0 }
                    .filter { $0 !== canonical }
                    .map(\.id)
            )

            for duplicateID in duplicateIDs {
                try remapReferences(
                    from: duplicateID,
                    to: canonical.id,
                    herd: herd,
                    in: context
                )
                if let duplicate = persisted.first(where: { $0.id == duplicateID }) {
                    context.delete(duplicate)
                }
            }

            if canonical.isDefault {
                setExclusiveDefault(canonical.id, in: herd, context: context)
            }
            try removeRetiredDefaults(in: herd, context: context)
            try normalizeDefault(in: herd, context: context)
        }
    }

    func setDefaultColor(id: UUID) throws {
        let herdID = try currentHerdID()
        try performWrite { context, herd in
            var target = try lookup.herdOwned(
                CDTagColorDefinition.self,
                id: id,
                herdID: herdID,
                in: context
            )

            if target == nil,
               let builtIn = TagColorDefaults.seedDefaultColors().first(where: { $0.id == id }) {
                target = makeManagedColor(from: builtIn, herd: herd, in: context)
            }

            guard let target else { return }
            setExclusiveDefault(target.id, in: herd, context: context)
        }
    }

    func deleteColors(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let herdID = try currentHerdID()
        let idsToDelete = Set(ids)

        try performWrite { context, herd in
            let persisted = try fetchPersistedColors(for: herd, in: context)
            for color in persisted where idsToDelete.contains(color.id) {
                if try isReferenced(colorID: color.id, herd: herd, in: context) {
                    preserveAsHiddenDefinition(color)
                } else {
                    context.delete(color)
                }
            }

            try normalizeDefault(in: herd, context: context)
        }
    }

    func reorder(colorIDs: [UUID]) throws {
        guard !colorIDs.isEmpty else { return }
        _ = try currentHerdID()

        try performWrite { context, herd in
            var persistedByID = Dictionary(
                uniqueKeysWithValues: try fetchPersistedColors(for: herd, in: context).map { ($0.id, $0) }
            )
            let builtInsByID = Dictionary(
                uniqueKeysWithValues: TagColorDefaults.seedDefaultColors().map { ($0.id, $0) }
            )
            var seen = Set<UUID>()

            for (order, id) in colorIDs.enumerated() where seen.insert(id).inserted {
                let target: CDTagColorDefinition
                if let persisted = persistedByID[id] {
                    if persisted.isHidden && builtInsByID[id] == nil {
                        continue
                    }
                    target = persisted
                } else if let builtIn = builtInsByID[id] {
                    target = makeManagedColor(from: builtIn, herd: herd, in: context)
                    persistedByID[id] = target
                } else {
                    continue
                }

                guard target.sortOrder != Int64(order) else { continue }
                target.sortOrder = Int64(order)
                target.updatedAt = .now
            }
        }
    }

    func restoreDefaultColors() throws {
        _ = try currentHerdID()
        try performWrite { context, herd in
            try removeRetiredDefaults(in: herd, context: context)

            let existingDefaultID = try fetchPersistedColors(for: herd, in: context)
                .first(where: { !$0.isHidden && $0.isDefault })?.id

            for builtIn in TagColorDefaults.seedDefaultColors() {
                let persisted = try fetchPersistedColors(for: herd, in: context)
                let builtInKey = TagColorLibraryRules.normalizedNameKey(builtIn.name)
                let byID = persisted.first { $0.id == builtIn.id }
                let byName = persisted.first {
                    TagColorLibraryRules.normalizedNameKey($0.name) == builtInKey
                }

                let target: CDTagColorDefinition
                if let byID {
                    target = byID
                } else {
                    target = makeManagedColor(from: builtIn, herd: herd, in: context)
                }

                if let byName, byName !== target {
                    try remapReferences(from: byName.id, to: target.id, herd: herd, in: context)
                    context.delete(byName)
                }

                target.name = builtIn.name
                target.prefix = builtIn.prefix
                target.red = builtIn.rgba.r
                target.green = builtIn.rgba.g
                target.blue = builtIn.rgba.b
                target.alpha = builtIn.rgba.a
                target.isHidden = false
                target.isDefault = existingDefaultID == nil ? builtIn.isDefault : target.id == existingDefaultID
            }

            try normalizeDefault(in: herd, context: context)
        }
    }

    private func currentHerdID() throws -> UUID {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        return herdID
    }

    private func performWrite(
        _ operation: (NSManagedObjectContext, CDHerd) throws -> Void
    ) throws {
        let herdID = try currentHerdID()
        let context = try contextFactory.makeWriteContext()

        try context.performAndWait {
            do {
                guard let herd = try lookup.herd(id: herdID, in: context) else {
                    throw HerdRepositoryError.missingHerd
                }
                try operation(context, herd)
                if context.hasChanges {
                    do {
                        try context.save()
                    } catch {
                        context.rollback()
                        throw CoreDataPersistenceError.saveFailed(
                            description: error.localizedDescription
                        )
                    }
                }
            } catch {
                if context.hasChanges {
                    context.rollback()
                }
                throw error
            }
        }
    }

    private func fetchPersistedColors(
        for herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> [CDTagColorDefinition] {
        let request = NSFetchRequest<CDTagColorDefinition>(
            entityName: CDTagColorDefinition.coreDataEntityName
        )
        request.predicate = NSPredicate(format: "herd == %@", herd)
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        return try context.fetch(request)
    }

    private func makeManagedColor(
        from snapshot: TagColorSnapshot,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) -> CDTagColorDefinition {
        let color = CDTagColorDefinition(context: context)
        color.id = snapshot.id
        color.name = snapshot.name
        color.prefix = snapshot.prefix
        color.red = snapshot.rgba.r
        color.green = snapshot.rgba.g
        color.blue = snapshot.rgba.b
        color.alpha = snapshot.rgba.a
        color.sortOrder = Int64(snapshot.sortOrder)
        color.isHidden = false
        color.isDefault = snapshot.isDefault
        color.createdAt = snapshot.createdAt
        color.updatedAt = snapshot.updatedAt
        color.herd = herd
        return color
    }

    private func setExclusiveDefault(
        _ id: UUID,
        in herd: CDHerd,
        context: NSManagedObjectContext
    ) {
        let colors = (herd.tagColors as? Set<CDTagColorDefinition>) ?? []
        for color in colors {
            color.isDefault = color.id == id
        }
    }

    private func normalizeDefault(
        in herd: CDHerd,
        context: NSManagedObjectContext
    ) throws {
        let colors = try fetchPersistedColors(for: herd, in: context).filter { !$0.isHidden }
        let selected = colors.filter(\.isDefault).sorted(by: defaultSort).first

        guard let selected else {
            return
        }

        for color in colors {
            color.isDefault = color.id == selected.id
        }
    }

    private func removeRetiredDefaults(
        in herd: CDHerd,
        context: NSManagedObjectContext
    ) throws {
        for color in try fetchPersistedColors(for: herd, in: context)
        where TagColorDefaults.retiredDefaultColorIDs.contains(color.id) {
            if try isReferenced(colorID: color.id, herd: herd, in: context) {
                preserveAsHiddenDefinition(color)
            } else {
                context.delete(color)
            }
        }
    }

    private func preserveAsHiddenDefinition(_ color: CDTagColorDefinition) {
        color.isHidden = true
        color.isDefault = false
        color.updatedAt = .now
    }

    private func remapReferences(
        from oldID: UUID,
        to replacementID: UUID,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws {
        guard oldID != replacementID else { return }

        guard let replacement = try lookup.herdOwned(
            CDTagColorDefinition.self,
            id: replacementID,
            herdID: herd.id,
            in: context
        ) else {
            return
        }

        let tagRequest = NSFetchRequest<CDAnimalTag>(entityName: CDAnimalTag.coreDataEntityName)
        tagRequest.predicate = NSPredicate(format: "herd == %@ AND color.id == %@", herd, oldID as NSUUID)
        for tag in try context.fetch(tagRequest) {
            tag.color = replacement
        }

        let checkRequest = NSFetchRequest<CDFieldCheckAnimalCheck>(
            entityName: CDFieldCheckAnimalCheck.coreDataEntityName
        )
        checkRequest.predicate = NSPredicate(format: "herd == %@", herd)
        for check in try context.fetch(checkRequest) {
            if check.rosterTagColorIDSnapshot == oldID { check.rosterTagColorIDSnapshot = replacementID }
            if check.damRosterTagColorIDSnapshot == oldID { check.damRosterTagColorIDSnapshot = replacementID }
        }

        let findingRequest = NSFetchRequest<CDFieldCheckFinding>(
            entityName: CDFieldCheckFinding.coreDataEntityName
        )
        findingRequest.predicate = NSPredicate(format: "herd == %@", herd)
        for finding in try context.fetch(findingRequest)
        where finding.animalDisplayTagColorIDSnapshot == oldID {
            finding.animalDisplayTagColorIDSnapshot = replacementID
        }

        let queueRequest = NSFetchRequest<CDWorkingQueueItem>(
            entityName: CDWorkingQueueItem.coreDataEntityName
        )
        queueRequest.predicate = NSPredicate(format: "herd == %@", herd)
        for item in try context.fetch(queueRequest) {
            if item.animalTagColorIDSnapshot == oldID { item.animalTagColorIDSnapshot = replacementID }
            if item.animalDamDisplayTagColorIDSnapshot == oldID { item.animalDamDisplayTagColorIDSnapshot = replacementID }
        }
    }

    private func isReferenced(
        colorID: UUID,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let tagRequest = NSFetchRequest<CDAnimalTag>(entityName: CDAnimalTag.coreDataEntityName)
        tagRequest.predicate = NSPredicate(format: "herd == %@ AND color.id == %@", herd, colorID as NSUUID)
        tagRequest.fetchLimit = 1
        if try context.count(for: tagRequest) > 0 { return true }

        let checks = NSFetchRequest<CDFieldCheckAnimalCheck>(
            entityName: CDFieldCheckAnimalCheck.coreDataEntityName
        )
        checks.predicate = NSPredicate(
            format: "herd == %@ AND (rosterTagColorIDSnapshot == %@ OR damRosterTagColorIDSnapshot == %@)",
            herd,
            colorID as NSUUID,
            colorID as NSUUID
        )
        checks.fetchLimit = 1
        if try context.count(for: checks) > 0 { return true }

        let findings = NSFetchRequest<CDFieldCheckFinding>(
            entityName: CDFieldCheckFinding.coreDataEntityName
        )
        findings.predicate = NSPredicate(
            format: "herd == %@ AND animalDisplayTagColorIDSnapshot == %@",
            herd,
            colorID as NSUUID
        )
        findings.fetchLimit = 1
        if try context.count(for: findings) > 0 { return true }

        let queue = NSFetchRequest<CDWorkingQueueItem>(
            entityName: CDWorkingQueueItem.coreDataEntityName
        )
        queue.predicate = NSPredicate(
            format: "herd == %@ AND (animalTagColorIDSnapshot == %@ OR animalDamDisplayTagColorIDSnapshot == %@)",
            herd,
            colorID as NSUUID,
            colorID as NSUUID
        )
        queue.fetchLimit = 1
        return try context.count(for: queue) > 0
    }

    private func persistedSort(
        _ lhs: CDTagColorDefinition,
        _ rhs: CDTagColorDefinition
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.updatedAt < rhs.updatedAt
    }

    private func defaultSort(
        _ lhs: CDTagColorDefinition,
        _ rhs: CDTagColorDefinition
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.sortOrder < rhs.sortOrder
    }

    private func snapshotSort(
        _ lhs: TagColorSnapshot,
        _ rhs: TagColorSnapshot
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
