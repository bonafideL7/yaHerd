@preconcurrency import CoreData
import Foundation

@MainActor
final class CoreDataTagColorRepository: TagColorRepository {
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    private let coordinationID: UUID
    private nonisolated let lookup: CoreDataLookup

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        coordinationID: UUID,
        lookup: CoreDataLookup
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.coordinationID = coordinationID
        self.lookup = lookup
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            coordinationID: assembly.coordinationID,
            lookup: assembly.lookup
        )
    }

    func fetchColors() throws -> [TagColorSnapshot] {
        let persisted = try fetchPersistedColors(includeHidden: false)
        var snapshotsByName = Dictionary(
            uniqueKeysWithValues: Self.seedBuiltIns().map {
                (TagColorLibraryRules.normalizedNameKey($0.name), $0)
            }
        )

        let builtInIDs = Set(Self.seedBuiltIns().map(\.id))
        var persistedBuiltIns: [UUID: TagColorSnapshot] = [:]
        for color in persisted {
            if builtInIDs.contains(color.id),
               let canonical = Self.seedBuiltIns().first(where: { $0.id == color.id }) {
                snapshotsByName.removeValue(
                    forKey: TagColorLibraryRules.normalizedNameKey(canonical.name)
                )
                persistedBuiltIns[color.id] = color
            } else {
                snapshotsByName[TagColorLibraryRules.normalizedNameKey(color.name)] = color
            }
        }

        var snapshots = Array(snapshotsByName.values) + Array(persistedBuiltIns.values)
        if let persistedDefaultID = persisted.first(where: \.isDefault)?.id {
            for index in snapshots.indices {
                snapshots[index].isDefault = snapshots[index].id == persistedDefaultID
            }
        }

        snapshots.sort(by: Self.snapshotSort)
        if !snapshots.contains(where: \.isDefault),
           let whiteIndex = snapshots.firstIndex(where: { $0.id == TagColorDefaults.whiteID }) {
            snapshots[whiteIndex].isDefault = true
        }
        return snapshots
    }

    func fetchColor(id: UUID) throws -> TagColorSnapshot? {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

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
                return Self.snapshot(from: persisted)
            }
            return Self.seedBuiltIns().first { $0.id == id }
        }
    }

    func upsert(_ color: TagColorSnapshot) throws {
        let cleanedName = TagColorLibraryRules.normalizedDisplayName(color.name)
        guard !cleanedName.isEmpty else { return }
        let cleanedPrefix = TagColorLibraryRules.normalizedPrefix(color.prefix, fallbackName: cleanedName)

        try performWrite(
            materializingTagColorIDs: upsertMaterializationCandidates(
                incomingID: color.id,
                cleanedName: cleanedName
            )
        ) { context, herd in
            let colors = try Self.fetchManagedColors(herd: herd, in: context)
            let existingByID = colors.first { $0.id == color.id }
            let nameKey = TagColorLibraryRules.normalizedNameKey(cleanedName)
            let existingByName = colors.first {
                TagColorLibraryRules.normalizedNameKey($0.name) == nameKey
            }
            let seedBuiltIns = Self.seedBuiltIns()
            let builtInIDs = Set(seedBuiltIns.map(\.id))
            let hasVisiblePersistedDefault = colors.contains {
                !$0.isDeleted && !$0.isHidden && $0.isDefault
            }
            let builtIn = seedBuiltIns.first {
                TagColorLibraryRules.normalizedNameKey($0.name) == nameKey
            }
            let incomingBuiltIn = seedBuiltIns.first { $0.id == color.id }
            let incomingIDIsBuiltIn = incomingBuiltIn != nil

            // Built-in ownership comes from the stable incoming UUID, not from whether that
            // definition has already been materialized. A built-in may absorb a custom-name
            // collision, but it must never overwrite or be remapped to another built-in.
            if incomingIDIsBuiltIn,
               let existingByName,
               existingByName.id != color.id,
               builtInIDs.contains(existingByName.id) {
                return
            }
            if let incomingBuiltIn,
               let builtIn,
               builtIn.id != incomingBuiltIn.id {
                return
            }

            if let incomingBuiltIn,
               existingByID == nil,
               existingByName == nil {
                let virtualIsDefault = !hasVisiblePersistedDefault && incomingBuiltIn.isDefault
                let requestedIsDefault = color.isDefault || virtualIsDefault
                let matchesVirtualDefinition = cleanedName == incomingBuiltIn.name
                    && cleanedPrefix == incomingBuiltIn.prefix
                    && color.rgba.r == incomingBuiltIn.rgba.r
                    && color.rgba.g == incomingBuiltIn.rgba.g
                    && color.rgba.b == incomingBuiltIn.rgba.b
                    && color.rgba.a == incomingBuiltIn.rgba.a
                    && requestedIsDefault == virtualIsDefault
                if matchesVirtualDefinition {
                    return
                }
            }

            let target: CDTagColorDefinition
            if let incomingBuiltIn {
                if let existingByID {
                    target = existingByID
                } else {
                    target = Self.insert(incomingBuiltIn, herd: herd, in: context)
                }
            } else if let builtIn {
                if let canonical = colors.first(where: { $0.id == builtIn.id }) {
                    target = canonical
                } else {
                    target = Self.insert(builtIn, herd: herd, in: context)
                }
            } else if let existingByName {
                target = existingByName
            } else if let existingByID {
                target = existingByID
            } else {
                target = CDTagColorDefinition(context: context)
                target.id = color.id
                target.createdAt = color.createdAt
                target.herd = herd
            }

            let isInsertion = target.isInserted
            let storedSortOrder = target.sortOrder
            let targetWasDefault = !isInsertion && target.isDefault
            let shouldInheritSeedDefault = isInsertion
                && !hasVisiblePersistedDefault
                && (incomingBuiltIn ?? builtIn)?.isDefault == true
            let desiredSortOrder: Int64
            if isInsertion, let ownedBuiltIn = incomingBuiltIn ?? builtIn {
                desiredSortOrder = Int64(ownedBuiltIn.sortOrder)
            } else if isInsertion {
                let persistedTail = colors
                    .filter { !$0.isDeleted && !$0.isHidden }
                    .map(\.sortOrder)
                    .max() ?? -1
                let builtInTail = seedBuiltIns.map { Int64($0.sortOrder) }.max() ?? -1
                desiredSortOrder = max(persistedTail, builtInTail) + 1
            } else {
                desiredSortOrder = storedSortOrder
            }
            let desiredDefault = color.isDefault
                || targetWasDefault
                || existingByID?.isDefault == true
                || existingByName?.isDefault == true
                || shouldInheritSeedDefault
            let targetChanged: Bool
            if isInsertion {
                targetChanged = true
            } else {
                targetChanged = target.name != cleanedName
                    || target.prefix != cleanedPrefix
                    || target.red != color.rgba.r
                    || target.green != color.rgba.g
                    || target.blue != color.rgba.b
                    || target.alpha != color.rgba.a
                    || target.sortOrder != desiredSortOrder
                    || target.isHidden
                    || target.isDefault != desiredDefault
            }

            if targetChanged {
                target.name = cleanedName
                target.prefix = cleanedPrefix
                target.red = color.rgba.r
                target.green = color.rgba.g
                target.blue = color.rgba.b
                target.alpha = color.rgba.a
                target.sortOrder = desiredSortOrder
                target.isHidden = false
                target.isDefault = desiredDefault
                target.updatedAt = isInsertion ? color.updatedAt : .now
            }

            var duplicates: [CDTagColorDefinition] = []
            if let existingByID, existingByID !== target { duplicates.append(existingByID) }
            if let existingByName,
               existingByName !== target,
               !builtInIDs.contains(existingByName.id),
               !duplicates.contains(where: { $0 === existingByName }) {
                duplicates.append(existingByName)
            }
            for duplicate in duplicates {
                try Self.remapColorReferences(
                    from: duplicate.id,
                    to: target,
                    herd: herd,
                    in: context
                )
                context.delete(duplicate)
            }
            try Self.normalizeDefaults(in: colors.filter { !$0.isDeleted } + [target])
        }
    }

    func setDefaultColor(id: UUID) throws {
        try performWrite(
            materializingTagColorIDs: candidateBuiltInTagColorIDs([id])
        ) { context, herd in
            var colors = try Self.fetchManagedColors(herd: herd, in: context)
            if !colors.contains(where: { $0.id == id }),
               let builtIn = Self.seedBuiltIns().first(where: { $0.id == id }) {
                let managed = Self.insert(builtIn, herd: herd, in: context)
                colors.append(managed)
            }
            guard colors.contains(where: { $0.id == id }) else { return }
            for color in colors {
                let shouldBeDefault = color.id == id
                guard color.isDefault != shouldBeDefault else { continue }
                color.isDefault = shouldBeDefault
                color.updatedAt = .now
            }
        }
    }

    func deleteColors(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let ids = Set(ids)
        try performWrite { context, herd in
            let colors = try Self.fetchManagedColors(herd: herd, in: context)
            for color in colors where ids.contains(color.id) {
                if TagColorDefaults.defaultColorIDs.contains(color.id) {
                    if try Self.hasPersistedReferences(to: color.id, herd: herd, in: context),
                       let canonical = Self.seedBuiltIns().first(where: { $0.id == color.id }) {
                        Self.applyCanonicalBuiltIn(
                            canonical,
                            to: color,
                            isDefault: color.isDefault
                        )
                    } else {
                        context.delete(color)
                    }
                } else if try Self.hasPersistedReferences(to: color.id, herd: herd, in: context) {
                    if !color.isHidden || color.isDefault {
                        color.isHidden = true
                        color.isDefault = false
                        color.updatedAt = .now
                    }
                } else {
                    context.delete(color)
                }
            }
            try Self.normalizeDefaults(in: colors.filter { !$0.isDeleted && !$0.isHidden })
        }
    }

    func reorder(colorIDs: [UUID]) throws {
        guard !colorIDs.isEmpty else { return }
        let order = Dictionary(uniqueKeysWithValues: colorIDs.enumerated().map { ($0.element, $0.offset) })
        try performWrite(
            materializingTagColorIDs: candidateBuiltInTagColorIDs(colorIDs)
        ) { context, herd in
            var colors = try Self.fetchManagedColors(herd: herd, in: context)
            let persistedIDs = Set(colors.map(\.id))
            let existingDefaultID = colors.first { $0.isDefault && !$0.isHidden }?.id
            for builtIn in Self.seedBuiltIns()
                where order[builtIn.id] != nil && !persistedIDs.contains(builtIn.id) {
                var snapshot = builtIn
                if existingDefaultID != nil {
                    snapshot.isDefault = false
                }
                colors.append(Self.insert(snapshot, herd: herd, in: context))
            }

            for color in colors {
                guard let position = order[color.id] else { continue }
                let desiredSortOrder = Int64(position)
                guard color.sortOrder != desiredSortOrder else { continue }
                color.sortOrder = desiredSortOrder
                color.updatedAt = .now
            }
        }
    }

    func restoreDefaultColors() throws {
        try performWrite(
            materializingTagColorIDs: TagColorDefaults.defaultColorIDs
        ) { context, herd in
            let colors = try Self.fetchManagedColors(herd: herd, in: context)
            for color in colors where TagColorDefaults.retiredDefaultColorIDs.contains(color.id) {
                if try Self.hasPersistedReferences(to: color.id, herd: herd, in: context) {
                    if !color.isHidden || color.isDefault {
                        color.isHidden = true
                        color.isDefault = false
                        color.updatedAt = .now
                    }
                } else {
                    context.delete(color)
                }
            }

            let existingDefaultID = colors.first(where: { $0.isDefault && !$0.isDeleted && !$0.isHidden })?.id
            let currentBuiltInIDs = Set(Self.seedBuiltIns().map(\.id))
            for defaultColor in Self.seedBuiltIns() {
                let normalizedDefaultName = TagColorLibraryRules.normalizedNameKey(defaultColor.name)
                let canonical = colors.first {
                    !$0.isDeleted && $0.id == defaultColor.id
                }
                let competingNameRows = colors.filter {
                    !$0.isDeleted
                        && $0 !== canonical
                        && !currentBuiltInIDs.contains($0.id)
                        && TagColorLibraryRules.normalizedNameKey($0.name) == normalizedDefaultName
                }

                let target: CDTagColorDefinition
                if let canonical {
                    target = canonical
                } else {
                    target = Self.insert(defaultColor, herd: herd, in: context)
                }

                let shouldRemainDefault = existingDefaultID.map { persistedDefaultID in
                    target.id == persistedDefaultID
                        || competingNameRows.contains(where: { $0.id == persistedDefaultID })
                } ?? (defaultColor.id == TagColorDefaults.whiteID)
                Self.applyCanonicalBuiltIn(
                    defaultColor,
                    to: target,
                    isDefault: shouldRemainDefault
                )

                for duplicate in competingNameRows {
                    try Self.remapColorReferences(
                        from: duplicate.id,
                        to: target,
                        herd: herd,
                        in: context
                    )
                    context.delete(duplicate)
                }
            }
            try Self.normalizeDefaults(
                in: try Self.fetchManagedColors(herd: herd, in: context).filter { !$0.isDeleted }
            )
        }
    }

    private func candidateBuiltInTagColorIDs(
        _ ids: [UUID]
    ) -> Set<UUID> {
        Set(ids).intersection(TagColorDefaults.defaultColorIDs)
    }

    private func upsertMaterializationCandidates(
        incomingID: UUID,
        cleanedName: String
    ) -> Set<UUID> {
        var candidates = candidateBuiltInTagColorIDs([incomingID])
        if let builtIn = Self.seedBuiltIns().first(where: {
            TagColorLibraryRules.normalizedNameKey($0.name)
                == TagColorLibraryRules.normalizedNameKey(cleanedName)
        }) {
            candidates.insert(builtIn.id)
        }
        return candidates
    }

    private func unmaterializedBuiltInTagColorIDs(
        _ ids: Set<UUID>,
        herdID: UUID
    ) throws -> Set<UUID> {
        guard !ids.isEmpty else {
            return []
        }

        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard try lookup.herd(id: herdID, in: context) != nil else {
                throw HerdRepositoryError.missingHerd
            }

            return Set(
                try ids.filter { id in
                    try lookup.herdOwned(
                        CDTagColorDefinition.self,
                        id: id,
                        herdID: herdID,
                        in: context
                    ) == nil
                }
            )
        }
    }

    private func assertMaterializationAvailable(
        candidateIDs: Set<UUID>,
        herdID: UUID
    ) throws {
        let missing = try unmaterializedBuiltInTagColorIDs(
            candidateIDs,
            herdID: herdID
        )
        try CoreDataTagColorMaterializationCoordinator.shared.assertAvailable(
            coordinationID: coordinationID,
            herdID: herdID,
            colorIDs: missing
        )
    }

    private func fetchPersistedColors(includeHidden: Bool) throws -> [TagColorSnapshot] {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return try Self.fetchManagedColors(herd: herd, in: context)
                .filter { includeHidden || !$0.isHidden }
                .map(Self.snapshot)
                .sorted(by: Self.snapshotSort)
        }
    }

    private func performWrite(
        materializingTagColorIDs: Set<UUID> = [],
        _ operation: @escaping @Sendable (NSManagedObjectContext, CDHerd) throws -> Void
    ) throws {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        try assertMaterializationAvailable(
            candidateIDs: materializingTagColorIDs,
            herdID: herdID
        )

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

    private nonisolated static func seedBuiltIns() -> [TagColorSnapshot] {
        let stableTimestamp = Date(timeIntervalSince1970: 0)
        return TagColorDefaults.seedDefaultColors().map { snapshot in
            var snapshot = snapshot
            snapshot.createdAt = stableTimestamp
            snapshot.updatedAt = stableTimestamp
            return snapshot
        }
    }

    private nonisolated static func fetchManagedColors(
        herd: CDHerd,
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

    private nonisolated static func insert(
        _ snapshot: TagColorSnapshot,
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

    private nonisolated static func snapshot(from color: CDTagColorDefinition) -> TagColorSnapshot {
        TagColorSnapshot(
            id: color.id,
            name: color.name,
            prefix: color.prefix,
            rgba: RGBAColor(r: color.red, g: color.green, b: color.blue, a: color.alpha),
            sortOrder: Int(color.sortOrder),
            isDefault: color.isDefault,
            createdAt: color.createdAt,
            updatedAt: color.updatedAt
        )
    }

    private nonisolated static func remapColorReferences(
        from oldColorID: UUID,
        to replacement: CDTagColorDefinition,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws {
        let tagRequest = NSFetchRequest<CDAnimalTag>(entityName: CDAnimalTag.coreDataEntityName)
        tagRequest.predicate = NSPredicate(
            format: "herd == %@ AND color.id == %@",
            herd,
            oldColorID as NSUUID
        )
        var affectedAnimals: [UUID: CDAnimal] = [:]
        for tag in try context.fetch(tagRequest) {
            tag.color = replacement
            affectedAnimals[tag.animal.id] = tag.animal
        }

        for animal in affectedAnimals.values {
            animal.editorRevision = UUID()
        }

        let checkRequest = NSFetchRequest<CDFieldCheckAnimalCheck>(
            entityName: CDFieldCheckAnimalCheck.coreDataEntityName
        )
        checkRequest.predicate = NSPredicate(
            format: "herd == %@ AND (rosterTagColorIDSnapshot == %@ OR damRosterTagColorIDSnapshot == %@)",
            herd,
            oldColorID as NSUUID,
            oldColorID as NSUUID
        )
        for check in try context.fetch(checkRequest) {
            if check.rosterTagColorIDSnapshot == oldColorID {
                check.rosterTagColorIDSnapshot = replacement.id
            }
            if check.damRosterTagColorIDSnapshot == oldColorID {
                check.damRosterTagColorIDSnapshot = replacement.id
            }
        }

        let findingRequest = NSFetchRequest<CDFieldCheckFinding>(
            entityName: CDFieldCheckFinding.coreDataEntityName
        )
        findingRequest.predicate = NSPredicate(
            format: "herd == %@ AND animalDisplayTagColorIDSnapshot == %@",
            herd,
            oldColorID as NSUUID
        )
        for finding in try context.fetch(findingRequest) {
            finding.animalDisplayTagColorIDSnapshot = replacement.id
        }

        let queueRequest = NSFetchRequest<CDWorkingQueueItem>(
            entityName: CDWorkingQueueItem.coreDataEntityName
        )
        queueRequest.predicate = NSPredicate(
            format: "herd == %@ AND (animalTagColorIDSnapshot == %@ OR animalDamDisplayTagColorIDSnapshot == %@)",
            herd,
            oldColorID as NSUUID,
            oldColorID as NSUUID
        )
        for item in try context.fetch(queueRequest) {
            if item.animalTagColorIDSnapshot == oldColorID {
                item.animalTagColorIDSnapshot = replacement.id
            }
            if item.animalDamDisplayTagColorIDSnapshot == oldColorID {
                item.animalDamDisplayTagColorIDSnapshot = replacement.id
            }
        }
    }

    private nonisolated static func applyCanonicalBuiltIn(
        _ snapshot: TagColorSnapshot,
        to color: CDTagColorDefinition,
        isDefault: Bool
    ) {
        let canonicalSortOrder = Int64(snapshot.sortOrder)
        let needsRepair = color.name != snapshot.name
            || color.prefix != snapshot.prefix
            || color.red != snapshot.rgba.r
            || color.green != snapshot.rgba.g
            || color.blue != snapshot.rgba.b
            || color.alpha != snapshot.rgba.a
            || color.sortOrder != canonicalSortOrder
            || color.isHidden
            || color.isDefault != isDefault

        guard needsRepair else { return }

        color.name = snapshot.name
        color.prefix = snapshot.prefix
        color.red = snapshot.rgba.r
        color.green = snapshot.rgba.g
        color.blue = snapshot.rgba.b
        color.alpha = snapshot.rgba.a
        color.sortOrder = canonicalSortOrder
        color.isHidden = false
        color.isDefault = isDefault
        color.updatedAt = .now
    }

    private nonisolated static func hasPersistedReferences(
        to colorID: UUID,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let tagRequest = NSFetchRequest<CDAnimalTag>(entityName: CDAnimalTag.coreDataEntityName)
        tagRequest.predicate = NSPredicate(format: "herd == %@ AND color.id == %@", herd, colorID as NSUUID)
        tagRequest.fetchLimit = 1
        if try context.count(for: tagRequest) > 0 { return true }

        let checkRequest = NSFetchRequest<CDFieldCheckAnimalCheck>(entityName: CDFieldCheckAnimalCheck.coreDataEntityName)
        checkRequest.predicate = NSPredicate(
            format: "herd == %@ AND (rosterTagColorIDSnapshot == %@ OR damRosterTagColorIDSnapshot == %@)",
            herd, colorID as NSUUID, colorID as NSUUID
        )
        checkRequest.fetchLimit = 1
        if try context.count(for: checkRequest) > 0 { return true }

        let findingRequest = NSFetchRequest<CDFieldCheckFinding>(entityName: CDFieldCheckFinding.coreDataEntityName)
        findingRequest.predicate = NSPredicate(
            format: "herd == %@ AND animalDisplayTagColorIDSnapshot == %@",
            herd, colorID as NSUUID
        )
        findingRequest.fetchLimit = 1
        if try context.count(for: findingRequest) > 0 { return true }

        let queueRequest = NSFetchRequest<CDWorkingQueueItem>(entityName: CDWorkingQueueItem.coreDataEntityName)
        queueRequest.predicate = NSPredicate(
            format: "herd == %@ AND (animalTagColorIDSnapshot == %@ OR animalDamDisplayTagColorIDSnapshot == %@)",
            herd, colorID as NSUUID, colorID as NSUUID
        )
        queueRequest.fetchLimit = 1
        return try context.count(for: queueRequest) > 0
    }

    private nonisolated static func normalizeDefaults(in colors: [CDTagColorDefinition]) throws {
        let defaults = colors.filter { $0.isDefault && !$0.isDeleted }
        guard defaults.count > 1 else { return }
        let selected = defaults.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.sortOrder < $1.sortOrder
        }.first
        for color in defaults where color !== selected {
            color.isDefault = false
            color.updatedAt = .now
        }
    }

    private nonisolated static func snapshotSort(_ lhs: TagColorSnapshot, _ rhs: TagColorSnapshot) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
