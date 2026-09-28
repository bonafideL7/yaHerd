@preconcurrency import CoreData
import Foundation

@MainActor
final class CoreDataTagColorRepository: TagColorRepository {
    private let repositoryContext: CoreDataSynchronousRepositoryContext
    nonisolated private let lookup: CoreDataLookup

    init(
        repositoryContext: CoreDataSynchronousRepositoryContext,
        lookup: CoreDataLookup
    ) {
        self.repositoryContext = repositoryContext
        self.lookup = lookup
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            repositoryContext: CoreDataSynchronousRepositoryContext(
                selection: selection,
                assembly: assembly
            ),
            lookup: assembly.lookup
        )
    }

    func fetchColors() throws -> [TagColorSnapshot] {
        try read { context, herd in
            try self.visibleSnapshots(in: context, herd: herd)
        }
    }

    func fetchColor(id: UUID) throws -> TagColorSnapshot? {
        try read { context, herd in
            if let persisted = try self.lookup.herdOwned(
                CDTagColorDefinition.self,
                id: id,
                herdID: herd.id,
                in: context
            ) {
                return persisted.toTagColorSnapshot()
            }
            return TagColorDefaults.seedDefaultColors().first { $0.id == id }
        }
    }

    func upsert(_ color: TagColorSnapshot) throws {
        let name = TagColorLibraryRules.normalizedDisplayName(color.name)
        guard !name.isEmpty else { return }
        let prefix = TagColorLibraryRules.normalizedPrefix(color.prefix, fallbackName: name)

        let builtIns = TagColorDefaults.seedDefaultColors()
        if let builtInByID = builtIns.first(where: { $0.id == color.id }),
           let builtInByName = builtIns.first(where: {
               TagColorLibraryRules.normalizedNameKey($0.name)
                   == TagColorLibraryRules.normalizedNameKey(name)
           }),
           builtInByID.id != builtInByName.id {
            // Both UUIDs are application constants. A conflicting edit cannot satisfy name
            // uniqueness without destroying one built-in identity, so leave both unchanged.
            return
        }

        try write { context, herd in
            let all = try self.persistedColors(in: context, herd: herd)
            let existingByID = all.first { $0.id == color.id }
            let sameName = all.filter {
                TagColorLibraryRules.normalizedNameKey($0.name)
                    == TagColorLibraryRules.normalizedNameKey(name)
            }

            let builtIns = TagColorDefaults.seedDefaultColors()
            let builtInByID = builtIns.first { $0.id == color.id }
            let builtInByName = builtIns.first {
                TagColorLibraryRules.normalizedNameKey($0.name)
                    == TagColorLibraryRules.normalizedNameKey(name)
            }
            let builtIn = builtInByID ?? builtInByName

            let canonical: CDTagColorDefinition
            if let builtIn {
                if let row = all.first(where: { $0.id == builtIn.id }) {
                    canonical = row
                } else {
                    canonical = CDTagColorDefinition(context: context)
                    canonical.id = builtIn.id
                    canonical.name = builtIn.name
                    canonical.prefix = builtIn.prefix
                    canonical.red = builtIn.rgba.r
                    canonical.green = builtIn.rgba.g
                    canonical.blue = builtIn.rgba.b
                    canonical.alpha = builtIn.rgba.a
                    canonical.sortOrder = Int64(builtIn.sortOrder)
                    canonical.isHidden = false
                    canonical.isDefault = false
                    canonical.createdAt = color.id == builtIn.id ? color.createdAt : builtIn.createdAt
                    canonical.updatedAt = color.id == builtIn.id ? color.updatedAt : builtIn.updatedAt
                    canonical.herd = herd
                }
            } else if let collision = sameName.first(where: { $0.id != color.id }) {
                canonical = collision
            } else if let existingByID {
                canonical = existingByID
            } else {
                canonical = CDTagColorDefinition(context: context)
                canonical.id = color.id
                canonical.name = name
                canonical.prefix = prefix
                canonical.red = color.rgba.r
                canonical.green = color.rgba.g
                canonical.blue = color.rgba.b
                canonical.alpha = color.rgba.a
                canonical.sortOrder = Int64(try self.nextVisibleSortOrder(in: context, herd: herd))
                canonical.isHidden = false
                canonical.isDefault = false
                canonical.createdAt = color.createdAt
                canonical.updatedAt = color.updatedAt
                canonical.herd = herd
            }

            let priorCreatedAt = canonical.createdAt
            let priorSortOrder = canonical.sortOrder
            let wasDefault = canonical.isDefault || existingByID?.isDefault == true
            canonical.name = name
            canonical.prefix = prefix
            canonical.red = color.rgba.r
            canonical.green = color.rgba.g
            canonical.blue = color.rgba.b
            canonical.alpha = color.rgba.a
            canonical.isHidden = false
            canonical.createdAt = priorCreatedAt
            canonical.updatedAt = max(canonical.updatedAt, color.updatedAt)
            canonical.sortOrder = priorSortOrder

            if canonical.id == color.id && existingByID == nil && builtIn == nil && sameName.isEmpty {
                canonical.createdAt = color.createdAt
                canonical.updatedAt = color.updatedAt
            }

            let duplicates = all.filter { row in
                row.objectID != canonical.objectID
                    && (row.id == color.id
                        || TagColorLibraryRules.normalizedNameKey(row.name)
                            == TagColorLibraryRules.normalizedNameKey(name))
            }

            var remaps: [UUID: UUID] = [:]
            for duplicate in duplicates where duplicate.id != canonical.id {
                remaps[duplicate.id] = canonical.id
                if duplicate.isDefault {
                    canonical.isDefault = true
                }
            }
            if color.id != canonical.id {
                remaps[color.id] = canonical.id
            }

            if !remaps.isEmpty {
                try self.remapReferences(remaps, in: context, herd: herd)
            }

            for duplicate in duplicates where duplicate.objectID != canonical.objectID {
                context.delete(duplicate)
            }

            if color.isDefault || wasDefault {
                try self.selectDefault(canonical.id, in: context, herd: herd)
            }
        }
    }

    func setDefaultColor(id: UUID) throws {
        try write { context, herd in
            var target = try self.lookup.herdOwned(
                CDTagColorDefinition.self,
                id: id,
                herdID: herd.id,
                in: context
            )

            if let builtIn = TagColorDefaults.seedDefaultColors().first(where: { $0.id == id }) {
                if let target {
                    self.applyDefinition(builtIn, to: target)
                    target.isHidden = false
                    target.updatedAt = max(target.updatedAt, Date())
                } else {
                    target = self.materialize(builtIn, in: context, herd: herd)
                }
            }

            guard target != nil else { return }
            try self.selectDefault(id, in: context, herd: herd)
        }
    }

    func deleteColors(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let requested = Set(ids)

        try write { context, herd in
            let all = try self.persistedColors(in: context, herd: herd)
            let builtInsByID = Dictionary(
                uniqueKeysWithValues: TagColorDefaults.seedDefaultColors().map { ($0.id, $0) }
            )
            for row in all where requested.contains(row.id) {
                if let builtIn = builtInsByID[row.id] {
                    if try self.isReferenced(colorID: row.id, in: context, herd: herd) {
                        self.applyDefinition(builtIn, to: row)
                        row.isHidden = true
                        row.isDefault = false
                        row.updatedAt = max(row.updatedAt, Date())
                    } else {
                        context.delete(row)
                    }
                } else {
                    row.isHidden = true
                    row.isDefault = false
                    row.updatedAt = max(row.updatedAt, Date())
                }
            }
        }
    }

    func reorder(colorIDs: [UUID]) throws {
        guard !colorIDs.isEmpty else { return }

        try write { context, herd in
            let visible = try self.visibleSnapshots(in: context, herd: herd)
            let visibleIDs = Set(visible.map(\.id))
            guard Set(colorIDs) == visibleIDs, colorIDs.count == visibleIDs.count else {
                return
            }

            var persistedByID = Dictionary(
                uniqueKeysWithValues: try self.persistedColors(in: context, herd: herd).map { ($0.id, $0) }
            )

            for snapshot in visible {
                if let row = persistedByID[snapshot.id] {
                    if row.isHidden,
                       let builtIn = TagColorDefaults.seedDefaultColors().first(where: { $0.id == snapshot.id }) {
                        self.applyDefinition(builtIn, to: row)
                        row.isHidden = false
                        row.updatedAt = max(row.updatedAt, Date())
                    }
                } else {
                    persistedByID[snapshot.id] = self.materialize(snapshot, in: context, herd: herd)
                }
            }

            for (index, id) in colorIDs.enumerated() {
                guard let row = persistedByID[id] else { continue }
                row.sortOrder = Int64(index)
                row.updatedAt = max(row.updatedAt, Date())
            }
        }
    }

    func restoreDefaultColors() throws {
        try write { context, herd in
            let allBefore = try self.persistedColors(in: context, herd: herd)
            let selectedDefaultID = allBefore.first(where: { $0.isDefault && !$0.isHidden })?.id

            for row in allBefore where TagColorDefaults.retiredDefaultColorIDs.contains(row.id) {
                if try self.isReferenced(colorID: row.id, in: context, herd: herd) {
                    row.isHidden = true
                    row.isDefault = false
                } else {
                    context.delete(row)
                }
            }

            for defaultColor in TagColorDefaults.seedDefaultColors() {
                let current = try self.lookup.herdOwned(
                    CDTagColorDefinition.self,
                    id: defaultColor.id,
                    herdID: herd.id,
                    in: context
                ) ?? self.materialize(defaultColor, in: context, herd: herd)

                current.name = defaultColor.name
                current.prefix = defaultColor.prefix
                current.red = defaultColor.rgba.r
                current.green = defaultColor.rgba.g
                current.blue = defaultColor.rgba.b
                current.alpha = defaultColor.rgba.a
                current.isHidden = false
                current.updatedAt = max(current.updatedAt, defaultColor.updatedAt)
            }

            if let selectedDefaultID {
                try self.selectDefault(selectedDefaultID, in: context, herd: herd)
            } else {
                try self.selectDefault(TagColorDefaults.whiteID, in: context, herd: herd)
            }
        }
    }

    private func read<Result>(
        _ operation: @Sendable (NSManagedObjectContext, CDHerd) throws -> Result
    ) throws -> Result {
        try repositoryContext.read(operation)
    }

    private func write<Result>(
        _ operation: @Sendable (NSManagedObjectContext, CDHerd) throws -> Result
    ) throws -> Result {
        try repositoryContext.write(operation)
    }

    private nonisolated func persistedColors(
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> [CDTagColorDefinition] {
        let request = NSFetchRequest<CDTagColorDefinition>(
            entityName: CDTagColorDefinition.coreDataEntityName
        )
        request.predicate = NSPredicate(format: "herd == %@", herd)
        let rows = try context.fetch(request)

        var seenIDs = Set<UUID>()
        for row in rows where !seenIDs.insert(row.id).inserted {
            throw CoreDataPersistenceError.duplicateApplicationID(
                entity: CDTagColorDefinition.coreDataEntityName,
                id: row.id,
                herdID: herd.id
            )
        }

        return rows
    }

    private nonisolated func visibleSnapshots(
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> [TagColorSnapshot] {
        let persisted = try persistedColors(in: context, herd: herd)
        let visiblePersisted = persisted.filter { !$0.isHidden }

        let visiblePersistedIDs = Set(visiblePersisted.map(\.id))
        var byName: [String: TagColorSnapshot] = [:]
        for builtIn in TagColorDefaults.seedDefaultColors()
        where !visiblePersistedIDs.contains(builtIn.id) {
            byName[TagColorLibraryRules.normalizedNameKey(builtIn.name)] = builtIn
        }

        let groups = Dictionary(grouping: visiblePersisted) {
            TagColorLibraryRules.normalizedNameKey($0.name)
        }
        for (key, rows) in groups {
            guard let row = canonicalColor(from: rows) else { continue }
            byName[key] = row.toTagColorSnapshot()
        }

        let selectedDefaultID = visiblePersisted
            .filter(\.isDefault)
            .sorted(by: defaultSort)
            .first?.id

        for key in Array(byName.keys) {
            guard var snapshot = byName[key] else { continue }
            snapshot.isDefault = selectedDefaultID.map { snapshot.id == $0 }
                ?? (snapshot.id == TagColorDefaults.whiteID)
            byName[key] = snapshot
        }

        return byName.values.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private nonisolated func canonicalColor(
        from rows: [CDTagColorDefinition]
    ) -> CDTagColorDefinition? {
        rows.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault && !$1.isDefault }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.updatedAt < $1.updatedAt
        }.first
    }

    private nonisolated func defaultSort(
        _ lhs: CDTagColorDefinition,
        _ rhs: CDTagColorDefinition
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.sortOrder < rhs.sortOrder
    }

    private nonisolated func nextVisibleSortOrder(
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> Int {
        let visible = try visibleSnapshots(in: context, herd: herd)
        return (visible.map(\.sortOrder).max() ?? -1) + 1
    }

    private nonisolated func materialize(
        _ snapshot: TagColorSnapshot,
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) -> CDTagColorDefinition {
        let row = CDTagColorDefinition(context: context)
        row.id = snapshot.id
        row.name = snapshot.name
        row.prefix = snapshot.prefix
        row.red = snapshot.rgba.r
        row.green = snapshot.rgba.g
        row.blue = snapshot.rgba.b
        row.alpha = snapshot.rgba.a
        row.sortOrder = Int64(snapshot.sortOrder)
        row.isHidden = false
        row.isDefault = snapshot.isDefault
        row.createdAt = snapshot.createdAt
        row.updatedAt = snapshot.updatedAt
        row.herd = herd
        return row
    }

    private nonisolated func selectDefault(
        _ id: UUID,
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws {
        for row in try persistedColors(in: context, herd: herd) {
            row.isDefault = !row.isHidden && row.id == id
        }
    }

    private nonisolated func applyDefinition(
        _ snapshot: TagColorSnapshot,
        to row: CDTagColorDefinition
    ) {
        row.name = snapshot.name
        row.prefix = snapshot.prefix
        row.red = snapshot.rgba.r
        row.green = snapshot.rgba.g
        row.blue = snapshot.rgba.b
        row.alpha = snapshot.rgba.a
    }

    private nonisolated func isReferenced(
        colorID: UUID,
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> Bool {
        if let color = try persistedColors(in: context, herd: herd)
            .first(where: { $0.id == colorID }),
           (color.tags?.count ?? 0) > 0 {
            return true
        }

        let checkRequest = NSFetchRequest<CDFieldCheckAnimalCheck>(
            entityName: CDFieldCheckAnimalCheck.coreDataEntityName
        )
        checkRequest.predicate = NSPredicate(
            format: "herd == %@ AND (rosterTagColorIDSnapshot == %@ OR damRosterTagColorIDSnapshot == %@)",
            herd,
            colorID as NSUUID,
            colorID as NSUUID
        )
        checkRequest.fetchLimit = 1
        if try !context.fetch(checkRequest).isEmpty {
            return true
        }

        let findingRequest = NSFetchRequest<CDFieldCheckFinding>(
            entityName: CDFieldCheckFinding.coreDataEntityName
        )
        findingRequest.predicate = NSPredicate(
            format: "herd == %@ AND animalDisplayTagColorIDSnapshot == %@",
            herd,
            colorID as NSUUID
        )
        findingRequest.fetchLimit = 1
        if try !context.fetch(findingRequest).isEmpty {
            return true
        }

        let queueRequest = NSFetchRequest<CDWorkingQueueItem>(
            entityName: CDWorkingQueueItem.coreDataEntityName
        )
        queueRequest.predicate = NSPredicate(
            format: "herd == %@ AND (animalTagColorIDSnapshot == %@ OR animalDamDisplayTagColorIDSnapshot == %@)",
            herd,
            colorID as NSUUID,
            colorID as NSUUID
        )
        queueRequest.fetchLimit = 1
        return try !context.fetch(queueRequest).isEmpty
    }

    private nonisolated func remapReferences(
        _ remaps: [UUID: UUID],
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws {
        guard !remaps.isEmpty else { return }

        let colorByID: [UUID: CDTagColorDefinition] = Dictionary(
            uniqueKeysWithValues: try persistedColors(in: context, herd: herd)
                .map { ($0.id, $0) }
        )

        let tagRequest = NSFetchRequest<CDAnimalTag>(entityName: CDAnimalTag.coreDataEntityName)
        tagRequest.predicate = NSPredicate(format: "herd == %@", herd)
        for tag in try context.fetch(tagRequest) {
            guard let oldID = tag.color?.id,
                  let replacementID = remaps[oldID],
                  let replacement = colorByID[replacementID] else { continue }
            tag.color = replacement
        }

        let checkRequest = NSFetchRequest<CDFieldCheckAnimalCheck>(
            entityName: CDFieldCheckAnimalCheck.coreDataEntityName
        )
        checkRequest.predicate = NSPredicate(format: "herd == %@", herd)
        for check in try context.fetch(checkRequest) {
            if let oldID = check.rosterTagColorIDSnapshot, let replacement = remaps[oldID] {
                check.rosterTagColorIDSnapshot = replacement
            }
            if let oldID = check.damRosterTagColorIDSnapshot, let replacement = remaps[oldID] {
                check.damRosterTagColorIDSnapshot = replacement
            }
        }

        let findingRequest = NSFetchRequest<CDFieldCheckFinding>(
            entityName: CDFieldCheckFinding.coreDataEntityName
        )
        findingRequest.predicate = NSPredicate(format: "herd == %@", herd)
        for finding in try context.fetch(findingRequest) {
            if let oldID = finding.animalDisplayTagColorIDSnapshot,
               let replacement = remaps[oldID] {
                finding.animalDisplayTagColorIDSnapshot = replacement
            }
        }

        let queueRequest = NSFetchRequest<CDWorkingQueueItem>(
            entityName: CDWorkingQueueItem.coreDataEntityName
        )
        queueRequest.predicate = NSPredicate(format: "herd == %@", herd)
        for item in try context.fetch(queueRequest) {
            if let oldID = item.animalTagColorIDSnapshot, let replacement = remaps[oldID] {
                item.animalTagColorIDSnapshot = replacement
            }
            if let oldID = item.animalDamDisplayTagColorIDSnapshot,
               let replacement = remaps[oldID] {
                item.animalDamDisplayTagColorIDSnapshot = replacement
            }
        }
    }
}

private extension CDTagColorDefinition {
    func toTagColorSnapshot() -> TagColorSnapshot {
        TagColorSnapshot(
            id: id,
            name: name,
            prefix: prefix,
            rgba: RGBAColor(r: red, g: green, b: blue, a: alpha),
            sortOrder: Int(sortOrder),
            isDefault: isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
