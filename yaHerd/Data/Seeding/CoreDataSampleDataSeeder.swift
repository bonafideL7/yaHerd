@preconcurrency import CoreData
import Foundation

/// Opt-in local development fixtures. Never invoked from app bootstrap.
@MainActor
final class CoreDataSampleDataSeeder: SampleDataSeeding {
    private let selection: any CurrentHerdSelectionReading
    private let assembly: CoreDataPersistenceAssembly
    private let mutationRecorder: any SuccessfulMutationRecording
    private let writePolicy: LocalDataWritePolicy

    init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly,
        mutationRecorder: any SuccessfulMutationRecording,
        writePolicy: LocalDataWritePolicy
    ) {
        self.selection = selection
        self.assembly = assembly
        self.mutationRecorder = mutationRecorder
        self.writePolicy = writePolicy
    }

    func canSeedSampleData() throws -> Bool {
        try writePolicy.validateCanWrite()
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        let context = assembly.contextFactory.makeReadContext()
        let lookup = assembly.lookup
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return try CoreDataSampleHerdFactory.isEmpty(herd: herd, in: context)
        }
    }

    func seedSampleDataIfNeeded() async throws -> Bool {
        try await seed(size: .compact)
    }

    func seedLargeSampleDataIfNeeded() async throws -> Bool {
        try await seed(size: .large)
    }

    private func seed(size: CoreDataSampleHerdFactory.Size) async throws -> Bool {
        try writePolicy.validateCanWrite()
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        // Working template CRUD is synchronous on the MainActor, so reserve
        // before the first suspension and hold through commit or rollback.
        // A second window's template write fails fast until this seed finishes.
        try assembly.sampleSeedWriteCoordinator.beginSeed()
        defer { assembly.sampleSeedWriteCoordinator.endSeed() }
        // Take the existing exclusive resident-write barrier before the
        // animal boundary, matching the order needed to avoid waiting on a
        // Field Check holding the other gate. This blocks parallel Animal,
        // Pasture, Working and Field Check writers across app scenes.
        await assembly.pastureResidentWriteCoordinator.acquirePastureDeletion()
        defer { assembly.pastureResidentWriteCoordinator.releasePastureDeletion() }
        await assembly.animalWriteBoundary.beginAnimalWrite()
        defer { assembly.animalWriteBoundary.endAnimalWrite() }
        // Also exclude concurrent materialization of canonical Tag Color IDs.

        let reserved = try CoreDataTagColorMaterializationCoordinator.shared.reserve(
            coordinationID: assembly.coordinationID,
            herdID: herdID,
            colorIDs: TagColorDefaults.defaultColorIDs,
            reservesDefaultSlot: true
        )
        defer {
            CoreDataTagColorMaterializationCoordinator.shared.release(
                coordinationID: assembly.coordinationID,
                herdID: herdID,
                colorIDs: reserved,
                releasesDefaultSlot: true
            )
        }
        let lookup = assembly.lookup
        let inserted = try await assembly.transactionExecutor.performWrite { context in
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return try CoreDataSampleHerdFactory.insert(
                size: size, herd: herd, in: context
            )
        }
        if inserted {
            // One successful commit invalidates every list, dashboard and workflow.
            mutationRecorder.recordSuccessfulMutation(reason: .animal)
        }
        return inserted
    }
}

/// One transaction creates complete Herd-owned rows and their snapshots.
/// No legacy SwiftData types, automatic reset, migrations or production schema edits.
enum CoreDataSampleHerdFactory {
    enum Size: Sendable, Equatable {
        case compact
        case large

        var animalCount: Int { self == .large ? 480 : 18 }
        var cowCount: Int { self == .large ? 180 : 7 }
        var heiferCount: Int { self == .large ? 100 : 4 }
        var bullCount: Int { self == .large ? 12 : 1 }
        var steerCount: Int { self == .large ? 56 : 2 }
    }

    /// Shared preflight for both the empty-state affordance and transactional gate.
    static func isEmpty(herd: CDHerd, in context: NSManagedObjectContext) throws -> Bool {
        // A group can exist without a Pasture. Do not overwrite or create
        // duplicate logical group names in a user-configured Herd.
        for name in ["Animal", "Pasture", "PastureGroup", "FieldCheckSession", "WorkingSession"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.predicate = NSPredicate(format: "herd == %@", herd)
            request.fetchLimit = 1
            if !(try context.fetch(request)).isEmpty {
                return false
            }
        }
        return true
    }

    static func insert(
        size: Size,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        // Re-check immediately before inserting; existing colors, templates and
        // reference data can be reused and must never be erased.
        guard try isEmpty(herd: herd, in: context) else { return false }

        let now = Date()
        let calendar = Calendar.current
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: now) ?? now
        }
        let existingColorsRequest = NSFetchRequest<CDTagColorDefinition>(
            entityName: CDTagColorDefinition.coreDataEntityName
        )
        existingColorsRequest.predicate = NSPredicate(format: "herd == %@", herd)
        let existingColors = try context.fetch(existingColorsRequest)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            existingColors, herdID: herd.id
        )
        var colors = Dictionary(uniqueKeysWithValues: existingColors.map { ($0.id, $0) })
        let hasDefault = existingColors.contains { $0.isDefault && !$0.isHidden }
        for snapshot in TagColorDefaults.seedDefaultColors() where colors[snapshot.id] == nil {
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
            color.isDefault = !hasDefault && snapshot.isDefault
            color.createdAt = now
            color.updatedAt = now
            color.herd = herd
            colors[color.id] = color
        }

        let statusRequest = NSFetchRequest<CDAnimalStatusReference>(
            entityName: CDAnimalStatusReference.coreDataEntityName
        )
        statusRequest.predicate = NSPredicate(format: "herd == %@", herd)
        var statusRefs = try context.fetch(statusRequest)
        for status in AnimalStatus.allCases {
            if statusRefs.contains(where: { $0.baseStatusRawValue == status.rawValue }) {
                continue
            }
            let reference = CDAnimalStatusReference(context: context)
            reference.id = UUID()
            reference.name = status.label
            reference.baseStatusRawValue = status.rawValue
            reference.herd = herd
            statusRefs.append(reference)
        }

        let groupNames = ["North Rotation", "South Rotation", "Rest & Holding"]
        let groups = groupNames.enumerated().map { index, name in
            let group = CDPastureGroup(context: context)
            group.id = UUID()
            group.name = name
            group.grazeDays = index == 2 ? 7 : 21
            group.restDays = index == 2 ? 14 : 35
            group.herd = herd
            return group
        }

        let pastureNames = [
            "NW Pasture", "SW Pasture", "NE Pasture", "SE Pasture",
            "LF Pasture", "Holding Pasture", "Wally's Pasture",
            "North Ridge", "Creek Bottom", "South Meadow",
            "East Ridge", "Upper Hay"
        ]
        let pastures: [CDPasture] = pastureNames.enumerated().map { index, name in
            let pasture = CDPasture(context: context)
            pasture.id = UUID()
            pasture.name = name
            pasture.sortOrder = Int64(index)
            let acreage = index == 5 ? 7.0 : Double(25 + (index * 17) % 70)
            pasture.acreage = NSNumber(value: acreage)
            pasture.usableAcreage = NSNumber(value: acreage * 0.8)
            pasture.targetAcresPerHead = NSNumber(value: 3.0)
            pasture.lastGrazedDate = daysAgo(15 + index * 4)
            pasture.group = groups[index < 4 ? 0 : index < 8 ? 1 : 2]
            pasture.herd = herd
            return pasture
        }

        var animals: [CDAnimal] = []
        animals.reserveCapacity(size.animalCount)
        for index in 0..<size.animalCount {
            let isCow = index < size.cowCount
            let isHeifer = index >= size.cowCount
                && index < size.cowCount + size.heiferCount
            let bullStart = size.cowCount + size.heiferCount
            let isBull = index >= bullStart && index < bullStart + size.bullCount
            let steerEnd = bullStart + size.bullCount + size.steerCount
            let isSteer = index >= bullStart + size.bullCount && index < steerEnd
            let isCalf = index >= steerEnd
            let sex: Sex = (isCow || isHeifer || (isCalf && index % 2 == 0)) ? .female : .male
            let ageInDays: Int
            if isCow { ageInDays = 1_750 + (index % 6) * 280 }
            else if isHeifer { ageInDays = 420 + (index % 16) * 20 }
            else if isBull { ageInDays = 1_450 + (index % 6) * 120 }
            else if isSteer { ageInDays = 470 + (index % 16) * 14 }
            else { ageInDays = 20 + (index % 10) * 24 }

            let status: AnimalStatus = size == .compact
                ? (index == size.animalCount - 1 ? .dead :
                    index == size.animalCount - 2 ? .sold : .active)
                : (index > 0 && index % 97 == 0) ? .dead
                : (index > 0 && index % 71 == 0) ? .sold : .active

            let animal = CDAnimal(context: context)
            animal.id = UUID()
            animal.editorRevision = UUID()
            animal.name = index < 4
                ? ["Jane", "Rudy", "Imogene", "Lottie"][index]
                : index % 17 == 0 ? "Sample \(index + 1)" : ""
            animal.sexRawValue = sex.rawValue
            animal.birthDate = daysAgo(ageInDays)
            animal.statusRawValue = status.rawValue
            animal.isArchived = index > 0 && index % 113 == 0
            animal.archivedAt = animal.isArchived ? daysAgo(12) : nil
            animal.archiveReason = animal.isArchived ? "Sample historical record" : nil
            animal.saleDate = status == .sold ? daysAgo(min(35, max(1, ageInDays - 1))) : nil
            animal.salePrice = status == .sold ? NSNumber(value: 1_200 + index * 3) : nil
            animal.reasonSold = status == .sold ? "Market sale" : nil
            animal.deathDate = status == .dead ? daysAgo(min(28, max(1, ageInDays - 1))) : nil
            animal.causeOfDeath = status == .dead ? "Sample natural loss" : nil
            animal.statusReference = statusRefs.first { $0.baseStatusRawValue == status.rawValue }
            let features = index % 9 == 0
                ? [DistinguishingFeature(description: "White facial marking", order: 0)]
                : index % 13 == 0
                ? [DistinguishingFeature(description: "Nursing calf", order: 0)]
                : []
            animal.distinguishingFeaturesData = try CoreDataAnimalPayloadCodec
                .encodeDistinguishingFeatures(features)
            animal.herd = herd
            animal.currentPasture = isBull ? pastures[3]
                : pastures[(index % 9 == 0 ? 5 : index % pastures.count)]
            animals.append(animal)

            // Keep a few untagged animals, and real retired-tag timelines.
            if index % 19 != 0 {
                let tag = CDAnimalTag(context: context)
                tag.id = UUID()
                tag.number = String(format: "%04d", index + 1)
                tag.isPrimary = true
                tag.isActive = true
                tag.assignedAt = animal.birthDate
                tag.removedAt = nil
                tag.color = colors[sex == .female ? TagColorDefaults.whiteID : TagColorDefaults.blueID]
                tag.animal = animal
                tag.herd = herd
            }
            if index % 13 == 0 {
                let retired = CDAnimalTag(context: context)
                retired.id = UUID()
                retired.number = String(format: "%04d", size.animalCount + index + 1)
                retired.isPrimary = false
                retired.isActive = false
                retired.assignedAt = animal.birthDate
                retired.removedAt = daysAgo(min(150, max(1, ageInDays - 1)))
                retired.color = colors[TagColorDefaults.purpleID]
                retired.animal = animal
                retired.herd = herd
            }

            if index % 4 == 0 {
                let history = CDMovementRecord(context: context)
                history.id = UUID()
                history.date = daysAgo(min(80 + index % 90, max(1, ageInDays - 1)))
                let from = pastures[(index + 1) % pastures.count]
                history.fromPastureIDSnapshot = from.id
                history.fromPastureNameSnapshot = try from.validatedName()
                history.toPastureIDSnapshot = animal.currentPasture?.id
                history.toPastureNameSnapshot = try animal.currentPasture.map { try $0.validatedName() }
                history.herd = herd
                history.animal = animal
            }

            if status != .active {
                let history = CDStatusRecord(context: context)
                history.id = UUID()
                history.date = status == .sold ? (animal.saleDate ?? now) : (animal.deathDate ?? now)
                history.oldStatusRawValue = AnimalStatus.active.rawValue
                history.newStatusRawValue = status.rawValue
                history.herd = herd
                history.animal = animal
            }

            if index % 3 == 0 || isSteer {
                let health = CDHealthRecord(context: context)
                health.id = UUID()
                health.date = daysAgo(min(2 + index % 120, max(1, ageInDays - 1)))
                health.treatment = isSteer ? "Banding" :
                    ["Vaccination", "Deworming", "Pinkeye Treatment", "Foot Trim"][index % 4]
                health.notes = index % 6 == 0 ? "Routine sample herd care" : nil
                health.herd = herd
                health.animal = animal
            }
        }

        // Bidirectional parent relationships are derived from real managed objects.
        let bullStart = size.cowCount + size.heiferCount
        let calfStart = bullStart + size.bullCount + size.steerCount
        for index in calfStart..<animals.count {
            animals[index].dam = animals[(index - calfStart) % size.cowCount]
            animals[index].sire = animals[bullStart + (index - calfStart) % size.bullCount]
        }
        // Cow classification is based on actual maternal offspring. When there
        // are fewer current-season calves than mature cows, older heifers fill
        // the remaining offspring links; they are still heifers themselves.
        let cowsWithoutNewCalves = max(0, size.cowCount - (animals.count - calfStart))
        for offset in 0..<cowsWithoutNewCalves {
            let olderOffspring = animals[size.cowCount + offset]
            olderOffspring.dam = animals[(animals.count - calfStart) + offset]
            olderOffspring.sire = animals[bullStart + offset % size.bullCount]
        }
        for index in stride(from: 0, to: size.cowCount + size.heiferCount, by: 4) {
            let animal = animals[index]
            guard animal.sexRawValue == Sex.female.rawValue else { continue }
            let check = CDPregnancyCheck(context: context)
            check.id = UUID()
            check.date = daysAgo(30 + index % 60)
            let result: PregnancyResult =
                index % 12 == 0 ? .pregnant : index % 8 == 0 ? .open : .unknown
            check.resultRawValue = result.rawValue
            check.technician = "Sample Veterinarian"
            check.estimatedDaysPregnant = result == .pregnant ? NSNumber(value: 120) : nil
            check.dueDate = result == .pregnant ? calendar.date(
                byAdding: .day, value: 160, to: now
            ) : nil
            check.sire = animals[bullStart]
            check.herd = herd
            check.animal = animal
        }

        // Existing template records remain unchanged; populate if none exist.
        let templateRequest = NSFetchRequest<CDWorkingTreatmentTemplate>(
            entityName: CDWorkingTreatmentTemplate.coreDataEntityName
        )
        templateRequest.predicate = NSPredicate(format: "herd == %@", herd)
        var templates = try context.fetch(templateRequest)
        let planned = [
            WorkingTreatmentPlanItem(
                name: "7-way vaccine",
                suggestedDose: WorkingTreatmentDose(
                    amount: 2, unit: .milliliter, route: .subcutaneous
                )
            ),
            WorkingTreatmentPlanItem(
                name: "Dewormer",
                suggestedDose: WorkingTreatmentDose(
                    amount: 5, unit: .milliliter, route: .oral
                )
            )
        ]
        let encodedPlan = try JSONEncoder().encode(planned)
        if templates.isEmpty {
            for name in ["Spring Working", "Fall Booster"] {
                let template = CDWorkingTreatmentTemplate(context: context)
                template.id = UUID()
                template.name = name
                template.itemsData = encodedPlan
                template.herd = herd
                templates.append(template)
            }
        }

        // Pasture checks: full roster snapshots plus independent findings.
        for pastureIndex in 0..<(size == .large ? 3 : 1) {
            let pasture = pastures[pastureIndex]
            let roster = animals.filter {
                $0.currentPasture === pasture && $0.statusRawValue == AnimalStatus.active.rawValue
                    && !$0.isArchived
            }
            let session = CDFieldCheckSession(context: context)
            session.id = UUID()
            session.startedAt = daysAgo(8 + pastureIndex * 7)
            session.completedAt = pastureIndex == 0 ? daysAgo(7) : nil
            session.notes = "Sample fence, water and animal count"
            session.expectedHeadCountSnapshot = Int64(roster.count)
            session.quickCowCount = 0
            session.quickHeiferCount = 0
            session.quickCalfCount = 0
            session.quickBullCount = 0
            session.quickSteerCount = 0
            session.pastureIDSnapshot = pasture.id
            session.pastureNameSnapshot = try pasture.validatedName()
            session.pastureArchivedAt = nil
            session.pasture = pasture
            session.herd = herd

            for (position, animal) in roster.enumerated() {
                let primary = CoreDataAnimalProjection.primaryTagFields(
                    CoreDataAnimalProjection.managedTags(animal)
                )
                let dam = animal.dam.map {
                    CoreDataAnimalProjection.primaryTagFields(
                        CoreDataAnimalProjection.managedTags($0)
                    )
                }
                let check = CDFieldCheckAnimalCheck(context: context)
                check.id = UUID()
                check.animalIDSnapshot = animal.id
                check.rosterTagNumberSnapshot = primary.number
                check.rosterTagColorIDSnapshot = primary.colorID
                check.damRosterTagNumberSnapshot = dam?.number
                check.damRosterTagColorIDSnapshot = dam?.colorID
                check.animalNameSnapshot = animal.name
                check.animalSexRawValueSnapshot = animal.sexRawValue
                check.animalTypeRawValueSnapshot = try CoreDataAnimalProjection
                    .animalType(animal).rawValue
                check.wasExpectedAtStart = true
                check.countedAt = position % 7 == 0 ? nil : session.startedAt
                check.missingConfirmedAt = nil
                check.herd = herd
                check.session = session
                check.animal = animal
            }

            let matching = roster.first
            let primary = matching.map {
                CoreDataAnimalProjection.primaryTagFields(
                    CoreDataAnimalProjection.managedTags($0)
                )
            }
            for findingIndex in 0..<3 {
                let finding = CDFieldCheckFinding(context: context)
                finding.id = UUID()
                finding.recordedAt = session.startedAt
                finding.typeRawValue = [
                    FieldCheckFindingType.generalObservation,
                    .pinkEye,
                    .waterIssue
                ][findingIndex].rawValue
                finding.severityRawValue = [
                    FieldCheckFindingSeverity.info, .warning, .critical
                ][findingIndex].rawValue
                finding.statusRawValue = [
                    FieldCheckFindingStatus.resolved, .monitoring, .open
                ][findingIndex].rawValue
                finding.note = ["Pasture checked", "Observe eye", "Check trough"][findingIndex]
                finding.pastureNameSnapshot = try pasture.validatedName()
                finding.animalIDSnapshot = findingIndex == 2 ? nil : matching?.id
                finding.animalDisplayTagNumberSnapshot =
                    findingIndex == 2 ? nil : primary?.number
                finding.animalDisplayTagColorIDSnapshot =
                    findingIndex == 2 ? nil : primary?.colorID
                finding.animalNameSnapshot =
                    findingIndex == 2 ? nil : matching?.name
                finding.herd = herd
                finding.session = session
                finding.animal = findingIndex == 2 ? nil : matching
            }
        }

        // Separate historical and in-progress Working sessions exercise the
        // library, pen, treatments and linked animal health/pregnancy records.
        for sessionIndex in 0..<(size == .large ? 3 : 2) {
            let source = pastures[sessionIndex == 0 ? 2 : sessionIndex == 1 ? 4 : 7]
            let session = CDWorkingSession(context: context)
            session.id = UUID()
            session.date = daysAgo(25 - sessionIndex * 8)
            let isActive = sessionIndex == 1
            session.statusRawValue = isActive
                ? WorkingSessionStatus.active.rawValue
                : WorkingSessionStatus.finished.rawValue
            session.sourcePasture = source
            session.sourcePastureIDSnapshot = source.id
            session.sourcePastureNameSnapshot = source.name
            session.treatmentTemplateNameSnapshot = "Spring Working"
            session.plannedTreatmentsData = encodedPlan
            session.herd = herd

            let candidates = animals.filter {
                $0.currentPasture === source &&
                $0.statusRawValue == AnimalStatus.active.rawValue &&
                !$0.isArchived
            }
            for (position, animal) in candidates.prefix(8).enumerated() {
                let primary = CoreDataAnimalProjection.primaryTagFields(
                    CoreDataAnimalProjection.managedTags(animal)
                )
                let dam = animal.dam.map {
                    CoreDataAnimalProjection.primaryTagFields(
                        CoreDataAnimalProjection.managedTags($0)
                    )
                }
                let item = CDWorkingQueueItem(context: context)
                item.id = UUID()
                let done = !isActive || position % 3 == 0
                item.statusRawValue = done
                    ? WorkingQueueStatus.done.rawValue
                    : WorkingQueueStatus.queued.rawValue
                item.completedAt = done ? session.date : nil
                item.animalIDSnapshot = animal.id
                item.animalTagNumberSnapshot = primary.number
                item.animalTagColorIDSnapshot = primary.colorID
                item.animalNameSnapshot = animal.name
                item.animalSexRawValueSnapshot = animal.sexRawValue
                item.animalDamDisplayTagNumberSnapshot = dam?.number
                item.animalDamDisplayTagColorIDSnapshot = dam?.colorID
                item.collectedFromPastureIDSnapshot = source.id
                item.collectedFromPastureNameSnapshot = source.name
                // The real completed-session workflow assigns an omitted
                // destination to the source Pasture, not to a nil destination.
                item.destinationPastureIDSnapshot = isActive ? nil : source.id
                item.destinationPastureNameSnapshot = isActive ? nil : source.name
                item.collectedFromPasture = source
                item.destinationPasture = isActive ? nil : source
                item.animal = animal
                item.session = session
                item.herd = herd
                if isActive {
                    animal.currentPasture = nil
                    animal.activeWorkingSession = session
                    animal.editorRevision = UUID()
                }

                if done {
                    let record = CDWorkingTreatmentRecord(context: context)
                    record.id = UUID()
                    record.date = session.date
                    record.treatmentItemID = planned[0].id
                    record.itemNameSnapshot = planned[0].name
                    record.given = true
                    record.doseAmount = NSNumber(value: 2)
                    record.doseUnitRawValue = WorkingTreatmentDoseUnit.milliliter.rawValue
                    record.administrationRouteRawValue =
                        WorkingTreatmentAdministrationRoute.subcutaneous.rawValue
                    record.animalIDSnapshot = animal.id
                    record.herd = herd
                    record.session = session
                    record.animal = animal

                    let health = CDHealthRecord(context: context)
                    health.id = UUID()
                    health.date = session.date
                    health.treatment = "Vaccination"
                    health.notes = "Sample working session"
                    health.herd = herd
                    health.animal = animal
                    health.workingSession = session
                }

                if done && position == 0 && animal.sexRawValue == Sex.female.rawValue {
                    let check = CDPregnancyCheck(context: context)
                    check.id = UUID()
                    check.date = session.date
                    check.resultRawValue = PregnancyResult.open.rawValue
                    check.technician = "Sample Working"
                    check.estimatedDaysPregnant = nil
                    check.dueDate = nil
                    check.sire = nil
                    check.herd = herd
                    check.animal = animal
                    check.workingSession = session
                }
            }
        }

        // All 18 entity types are represented by live native Core Data rows.
        // The transaction executor will rollback every inserted object on any failure.
        return true
    }
}
