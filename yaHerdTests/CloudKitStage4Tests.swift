@preconcurrency import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CloudKitStage4Tests: XCTestCase {
    func testHistoryClassifiesEveryPersistedEntityIncludingChildOnlyChanges() {
        let groups: [(DataMutationReason, Set<String>)] = [
            (.animal, ["Animal", "AnimalTag", "AnimalStatusReference", "MovementRecord",
                       "StatusRecord", "HealthRecord", "PregnancyCheck"]),
            (.pasture, ["Pasture", "PastureGroup"]),
            (.fieldCheck, ["FieldCheckSession", "FieldCheckAnimalCheck", "FieldCheckFinding"]),
            (.working, ["WorkingSession", "WorkingQueueItem", "WorkingTreatmentRecord",
                        "WorkingTreatmentTemplate"]),
            (.tagColor, ["TagColorDefinition"]),
            (.herd, ["Herd"])
        ]
        for (reason, names) in groups {
            for name in names {
                let change = PersistentHistoryChanges(
                    storeID: "private", entityNames: [name], requiresFullRefresh: false
                )
                XCTAssertEqual(change.storeID, "private")
                XCTAssertEqual(change.reasons, [reason], name)
                XCTAssertEqual(change.requiresFullRefresh, reason == .herd, name)
            }
        }
    }

    func testHistoryUnknownAndEmptyChangesRequireBroadInvalidation() {
        for names: Set<String> in [[], ["UnrecognizedEntity"], ["Animal", "UnrecognizedEntity"]] {
            let change = PersistentHistoryChanges(
                storeID: "shared", entityNames: names, requiresFullRefresh: false
            )
            XCTAssertTrue(change.requiresFullRefresh)
        }
        let change = PersistentHistoryChanges(
            storeID: "shared", entityNames: ["Animal"], requiresFullRefresh: true
        )
        XCTAssertTrue(change.requiresFullRefresh)
    }

    func testMixedRemoteBatchPublishesOneRevisionPerArea() {
        let center = ApplicationMutationCenter()
        let changes = PersistentHistoryChanges(
            storeID: "shared", entityNames: ["AnimalTag", "WorkingTreatmentRecord", "PastureGroup"],
            requiresFullRefresh: false
        )
        center.recordRemoteChanges(storeID: changes.storeID, reasons: changes.reasons,
                                   requiresFullRefresh: changes.requiresFullRefresh)
        XCTAssertEqual(center.currentSequence, 1)
        XCTAssertEqual(center.latestEvent?.source,
                       .remote(storeID: "shared", reasons: [.animal, .working, .pasture], requiresFullRefresh: false))
        XCTAssertEqual(center.latestEvent?.affectedAreas, Set(ApplicationFeatureArea.allCases))
        for area in ApplicationFeatureArea.allCases {
            XCTAssertEqual(center.revision(for: area), 1)
        }
    }

    func testFieldCheckBatchOnlyInvalidatesDependentAreasAndUnknownBatchInvalidatesAll() {
        let center = ApplicationMutationCenter()
        center.recordRemoteChanges(storeID: "private", reasons: [.fieldCheck], requiresFullRefresh: false)
        XCTAssertEqual(center.latestEvent?.affectedAreas, [.home, .dashboard, .pastures, .fieldChecks])
        XCTAssertEqual(center.animalRevision, 0)
        XCTAssertEqual(center.workingSessionRevision, 0)
        center.recordRemoteChanges(storeID: "private", reasons: [], requiresFullRefresh: false)
        XCTAssertEqual(center.latestEvent?.affectedAreas, Set(ApplicationFeatureArea.allCases))
        XCTAssertEqual(center.animalRevision, 1)
        XCTAssertEqual(center.fieldCheckRevision, 2)
    }

    func testRevisionSubscriptionCatchesUpAndCoalescesBursts() async {
        let center = ApplicationMutationCenter()
        center.recordRemoteChanges(storeID: "private", reasons: [.animal], requiresFullRefresh: false)
        let stream = center.revisions(for: .animals, after: 0)
        center.recordRemoteChanges(storeID: "shared", reasons: [.animal], requiresFullRefresh: false)
        center.recordRemoteChanges(storeID: "shared", reasons: [.tagColor], requiresFullRefresh: false)
        var iterator = stream.makeAsyncIterator()
        let revision = await iterator.next()
        XCTAssertEqual(revision, 3)
    }

    func testHistoryWakeupsCoalesceAndFinish() async {
        let wakeups = CoreDataHistoryWakeups()
        wakeups.requestProcessing()
        wakeups.requestProcessing()
        wakeups.finish()
        var iterator = wakeups.stream.makeAsyncIterator()
        let first: Void? = await iterator.next()
        let second: Void? = await iterator.next()
        XCTAssertNotNil(first)
        XCTAssertNil(second)
    }

    func testCheckpointPathsAreStoreQualified() {
        let directory = URL(fileURLWithPath: "/tmp/stage4", isDirectory: true)
        let owned = CoreDataHistoryStore(identifier: "private", url: directory.appendingPathComponent("owned.sqlite"))
        let shared = CoreDataHistoryStore(identifier: "shared", url: directory.appendingPathComponent("shared.sqlite"))
        XCTAssertNotEqual(owned.checkpointURL, shared.checkpointURL)
        XCTAssertEqual(owned.checkpointURL.lastPathComponent, "owned.sqlite.history-checkpoint-v1")
        XCTAssertNotEqual(owned, CoreDataHistoryStore(identifier: "replacement", url: owned.url))
    }

    func testStoreActivityRejectsLateStartAndDuplicateCompletion() {
        let start = Date(timeIntervalSince1970: 100)
        let pending = CloudStoreActivity.Outcome(startDate: start, endDate: nil, state: .waiting)
        let completed = CloudStoreActivity.Outcome(startDate: start, endDate: start.addingTimeInterval(1), state: .complete)
        XCTAssertTrue(completed.follows(pending))
        XCTAssertFalse(pending.follows(completed))
        XCTAssertFalse(completed.follows(completed))
        let next = CloudStoreActivity.Outcome(startDate: start.addingTimeInterval(2), endDate: nil, state: .waiting)
        XCTAssertTrue(next.follows(completed))
    }

    func testTimelineCanReloadAfterFailureAndAfterSuccessfulRead() {
        let herd = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herd)
        let model = AnimalTimelineContainerViewModel()
        let reader = TimelineReader()
        let animal = UUID()
        func load() {
            model.load(animalID: animal, using: reader, selection: selection,
                       originatingHerdID: herd, originatingSelectionRevision: 0)
        }
        reader.fail = true
        load()
        XCTAssertNotNil(model.errorMessage)
        reader.fail = false
        reader.events = [AnimalTimelineEvent(id: "one", date: .distantPast, type: .birth, title: "Birth", details: nil)]
        load()
        XCTAssertEqual(model.events.map(\.id), ["one"])
        XCTAssertNil(model.errorMessage)
        reader.events = []
        load()
        XCTAssertTrue(model.events.isEmpty)
        selection.deferCurrentHerdUntilImportReady()
        reader.events = [AnimalTimelineEvent(id: "two", date: .now, type: .health, title: "Health", details: nil)]
        load()
        XCTAssertTrue(model.events.isEmpty)
    }

    func testPastureGroupRefreshFailureAndDeletionRetainOpeningEditorSnapshot() {
        let herd = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herd)
        let group = PastureGroupDetailSnapshot(id: UUID(), name: "North", grazeDays: 7, restDays: 21, pastures: [])
        let reader = GroupReader()
        reader.detail = group
        let model = PastureGroupDetailViewModel()
        func load() {
            model.load(groupID: group.id, using: reader, expectedHerdID: herd,
                       expectedSelectionRevision: 0, selection: selection)
        }
        load()
        model.beginEditing(expectedHerdID: herd, expectedSelectionRevision: 0, selection: selection)
        XCTAssertEqual(model.editingGroup, group)
        reader.fail = true
        load()
        XCTAssertNil(model.detail)
        XCTAssertEqual(model.editingGroup, group)
        reader.fail = false
        reader.detail = nil
        load()
        XCTAssertNil(model.detail)
        XCTAssertEqual(model.editingGroup, group)
        selection.deferCurrentHerdUntilImportReady()
        load()
        XCTAssertNil(model.editingGroup)
    }

    func testFinishDraftReconcilesEditedClearedNewAndRemovedAssignments() {
        let source = UUID(), first = UUID(), second = UUID(), third = UUID()
        let edited = UUID(), cleared = UUID(), untouched = UUID(), removed = UUID(), added = UUID()
        let valid: Set<UUID> = [first, second, third]
        let opening = WorkingFinishDestinationDraft.reconcile(
            queueItems: [item(edited, first), item(cleared, first), item(untouched, first), item(removed, first)],
            sourcePastureID: source, validDestinations: valid,
            savedExceptions: [:], selectedIDs: [], destinations: [:]
        )
        let recovered = WorkingFinishDestinationDraft.reconcile(
            queueItems: [item(edited, second), item(cleared, first), item(untouched, second), item(added, third)],
            sourcePastureID: source, validDestinations: valid, savedExceptions: opening.savedExceptions,
            selectedIDs: [edited, untouched, removed],
            destinations: [edited: third, untouched: first, removed: first]
        )
        XCTAssertEqual(recovered.selectedIDs, [edited, untouched, added])
        XCTAssertEqual(recovered.destinations, [edited: third, untouched: second, added: third])
    }

    func testFinishDraftKeepsExplicitlyClearedDestinationAndDoesNotTrustFailedPastureRead() {
        let source = UUID(), destination = UUID(), animal = UUID()
        let opening = WorkingFinishDestinationDraft.reconcile(
            queueItems: [item(animal, destination)], sourcePastureID: source,
            validDestinations: [destination], savedExceptions: [:], selectedIDs: [], destinations: [:]
        )
        let failedPastureRead = WorkingFinishDestinationDraft.reconcile(
            queueItems: [item(animal, destination)], sourcePastureID: source,
            validDestinations: nil, savedExceptions: opening.savedExceptions,
            selectedIDs: [animal], destinations: [:]
        )
        XCTAssertEqual(failedPastureRead.selectedIDs, [animal])
        XCTAssertTrue(failedPastureRead.destinations.isEmpty)
        let missingDestination = WorkingFinishDestinationDraft.reconcile(
            queueItems: [item(animal, destination)], sourcePastureID: nil,
            validDestinations: [], savedExceptions: opening.savedExceptions,
            selectedIDs: opening.selectedIDs, destinations: opening.destinations
        )
        XCTAssertEqual(missingDestination.selectedIDs, [animal])
        XCTAssertTrue(missingDestination.destinations.isEmpty)
    }

    func testSQLiteHistorySuppressesLocalWritesAndResumesIndependentStoreCheckpoints() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL, mirroringEnabled: false
        )
        let factory = assembly.contextFactory
        let stores = try factory.historyStores()
        XCTAssertEqual(stores.count, 2)
        let owned = try XCTUnwrap(stores.first { $0.url == harness.storeURL })
        let shared = try XCTUnwrap(stores.first { $0.identifier != owned.identifier })

        let initial = await processHistory(factory)
        XCTAssertEqual(Set(initial.changes.map(\.storeID)), Set(stores.map(\.identifier)))
        XCTAssertTrue(initial.changes.allSatisfy(\.requiresFullRefresh))
        let ownedCheckpoint = try Data(contentsOf: owned.checkpointURL)
        let sharedCheckpoint = try Data(contentsOf: shared.checkpointURL)

        try insertHerd(in: owned, using: factory, author: nil)
        let local = await processHistory(factory)
        XCTAssertTrue(local.changes.isEmpty)
        XCTAssertNotEqual(try Data(contentsOf: owned.checkpointURL), ownedCheckpoint)
        XCTAssertEqual(try Data(contentsOf: shared.checkpointURL), sharedCheckpoint)

        try insertHerd(in: shared, using: factory, author: "external-import")
        let remote = await processHistory(factory)
        XCTAssertEqual(remote.changes.map(\.storeID), [shared.identifier])
        XCTAssertEqual(remote.changes.first?.reasons, [.herd])
        let replay = await processHistory(factory)
        XCTAssertTrue(replay.changes.isEmpty, "A new consumer must resume the durable cursor.")
    }

    func testSQLiteHistoryDoesNotAdvanceUnacknowledgedPageAndRebuildsCorruptCursor() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL, mirroringEnabled: false
        )
        let factory = assembly.contextFactory
        let stores = try factory.historyStores()
        let owned = try XCTUnwrap(stores.first { $0.url == harness.storeURL })
        let shared = try XCTUnwrap(stores.first { $0.identifier != owned.identifier })
        _ = await processHistory(factory)
        let ownedCheckpoint = try Data(contentsOf: owned.checkpointURL)
        let sharedCheckpoint = try Data(contentsOf: shared.checkpointURL)

        try insertHerd(in: owned, using: factory, author: "older-process")
        let rejected = await processHistory(factory, acknowledge: false)
        XCTAssertEqual(rejected.changes.map(\.storeID), [owned.identifier, owned.identifier])
        XCTAssertEqual(try Data(contentsOf: owned.checkpointURL), ownedCheckpoint)

        let recovered = await processHistory(factory)
        XCTAssertEqual(recovered.changes.map(\.storeID), [owned.identifier])
        XCTAssertNotEqual(try Data(contentsOf: owned.checkpointURL), ownedCheckpoint)

        try Data("not a checkpoint".utf8).write(to: owned.checkpointURL)
        let rebuilt = await processHistory(factory)
        XCTAssertEqual(rebuilt.changes.map(\.storeID), [owned.identifier])
        XCTAssertEqual(rebuilt.changes.first?.requiresFullRefresh, true)
        XCTAssertEqual(try Data(contentsOf: shared.checkpointURL), sharedCheckpoint)
        let replay = await processHistory(factory)
        XCTAssertTrue(replay.changes.isEmpty)
    }

    func testSQLiteHistoryPagesDoNotSkipRemoteTransactionsAcrossLocalWrites() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL, mirroringEnabled: false
        )
        let factory = assembly.contextFactory
        let owned = try XCTUnwrap(factory.historyStores().first { $0.url == harness.storeURL })
        _ = await processHistory(factory)

        // Put remote changes on both sides of the 128-transaction page boundary.
        // Local transactions must advance the cursor without hiding remote ones.
        try insertHerd(in: owned, using: factory, author: "external-import")
        for _ in 0..<127 {
            try insertHerd(in: owned, using: factory, author: nil)
        }
        try insertHerd(in: owned, using: factory, author: "external-import")

        // Establish the actual persisted transaction count and newest token
        // independently of the consumer's requested fetch limit.
        let context = factory.makeReadContext()
        let newestTransactionNumber = try context.performAndWait {
            let store = try XCTUnwrap(context.persistentStoreCoordinator?.persistentStores.first {
                $0.identifier == owned.identifier
            })
            let request = NSPersistentHistoryChangeRequest.fetchHistory(
                after: nil as NSPersistentHistoryToken?
            )
            request.affectedStores = [store]
            request.resultType = .transactionsOnly
            let result = try XCTUnwrap(try context.execute(request) as? NSPersistentHistoryResult)
            let transactions = try XCTUnwrap(result.result as? [NSPersistentHistoryTransaction])
            XCTAssertEqual(transactions.count, 129)
            return try XCTUnwrap(transactions.map(\.transactionNumber).max())
        }

        let consumed = await processHistory(factory)
        XCTAssertEqual(consumed.changes.map(\.storeID), [owned.identifier, owned.identifier])
        XCTAssertTrue(consumed.changes.allSatisfy { $0.reasons == [.herd] })
        let checkpoint = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: owned.checkpointURL)) as? [String: Any]
        )
        XCTAssertEqual(checkpoint["transactionNumber"] as? Int64, newestTransactionNumber)

        let resumed = await processHistory(factory)
        XCTAssertTrue(resumed.changes.isEmpty)
    }

    func testSQLiteHistoryRejectedStoreDoesNotBlockIndependentStore() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL, mirroringEnabled: false
        )
        let factory = assembly.contextFactory
        let stores = try factory.historyStores()
        let rejected = try XCTUnwrap(stores.first)
        let accepted = try XCTUnwrap(stores.last)
        XCTAssertNotEqual(rejected, accepted)
        _ = await processHistory(factory)
        let rejectedCheckpoint = try Data(contentsOf: rejected.checkpointURL)
        let acceptedCheckpoint = try Data(contentsOf: accepted.checkpointURL)
        try insertHerd(in: rejected, using: factory, author: "external-import")
        try insertHerd(in: accepted, using: factory, author: "external-import")

        let recorder = HistoryRecorder()
        let wakeups = CoreDataHistoryWakeups()
        wakeups.requestProcessing()
        wakeups.finish()
        await CoreDataPersistentHistoryConsumer(contextFactory: factory).run(
            wakeups: wakeups, refreshInventory: {},
            publish: { changes in
                recorder.changes.append(changes)
                return changes.storeID != rejected.identifier
            }
        )

        XCTAssertEqual(recorder.changes.filter { $0.storeID == rejected.identifier }.count, 2)
        XCTAssertEqual(recorder.changes.filter { $0.storeID == accepted.identifier }.count, 1)
        XCTAssertEqual(try Data(contentsOf: rejected.checkpointURL), rejectedCheckpoint)
        XCTAssertNotEqual(try Data(contentsOf: accepted.checkpointURL), acceptedCheckpoint)

        let resumed = await processHistory(factory)
        XCTAssertEqual(resumed.changes.map(\.storeID), [rejected.identifier])
    }

    func testSQLiteHistoryRebuildsInconsistentCursorDespiteBroadInvalidation() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL, mirroringEnabled: false
        )
        let factory = assembly.contextFactory
        let owned = try XCTUnwrap(factory.historyStores().first { $0.url == harness.storeURL })
        try insertHerd(in: owned, using: factory, author: "external-import")
        _ = await processHistory(factory)
        var checkpoint = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: owned.checkpointURL)) as? [String: Any]
        )
        checkpoint["transactionNumber"] = 1_000_000
        try JSONSerialization.data(withJSONObject: checkpoint).write(to: owned.checkpointURL)

        try insertHerd(in: owned, using: factory, author: "external-import")
        let recovered = await processHistory(factory)
        XCTAssertEqual(recovered.changes.map(\.storeID), [owned.identifier])
        XCTAssertEqual(recovered.changes.first?.requiresFullRefresh, true)
        let saved = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: owned.checkpointURL)) as? [String: Any]
        )
        let number = try XCTUnwrap(saved["transactionNumber"] as? Int64)
        XCTAssertLessThan(number, 1_000_000)
        let replay = await processHistory(factory)
        XCTAssertTrue(replay.changes.isEmpty)
    }

    @MainActor
    private final class HistoryRecorder {
        var changes: [PersistentHistoryChanges] = []
    }

    private func processHistory(
        _ factory: CoreDataContextFactory, acknowledge: Bool = true
    ) async -> HistoryRecorder {
        let recorder = HistoryRecorder()
        let wakeups = CoreDataHistoryWakeups()
        wakeups.requestProcessing()
        wakeups.finish()
        await CoreDataPersistentHistoryConsumer(contextFactory: factory).run(
            wakeups: wakeups, refreshInventory: {},
            publish: { changes in
                recorder.changes.append(changes)
                return acknowledge
            }
        )
        return recorder
    }

    private func insertHerd(
        in store: CoreDataHistoryStore, using factory: CoreDataContextFactory, author: String?
    ) throws {
        let context = try factory.makeWriteContext()
        try context.performAndWait {
            if let author { context.transactionAuthor = author }
            let target = try XCTUnwrap(context.persistentStoreCoordinator?.persistentStores.first {
                $0.identifier == store.identifier
            })
            let herd = CDHerd(context: context)
            herd.id = UUID()
            herd.name = "History fixture"
            herd.createdAt = Date(timeIntervalSince1970: 100)
            herd.updatedAt = Date(timeIntervalSince1970: 100)
            context.assign(herd, to: target)
            try context.save()
        }
    }

    private func item(_ id: UUID, _ destination: UUID?) -> WorkingQueueItemSnapshot {
        WorkingQueueItemSnapshot(
            id: id, status: .queued, completedAt: nil, animalID: UUID(),
            animalDisplayTagNumber: "1", animalDisplayTagColorID: nil,
            animalDamDisplayTagNumber: nil, animalDamDisplayTagColorID: nil,
            animalSex: .female, collectedFromPastureName: nil,
            destinationPastureID: destination, destinationPastureName: nil
        )
    }

    private enum ReadError: Error { case unavailable }

    private final class TimelineReader: AnimalTimelineReading {
        var events: [AnimalTimelineEvent] = []
        var fail = false
        func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent] {
            if fail { throw ReadError.unavailable }
            return events
        }
    }

    private final class GroupReader: PastureGroupDetailReader, PastureListReader {
        var detail: PastureGroupDetailSnapshot?
        var fail = false
        func fetchPastureGroupDetail(id: UUID) throws -> PastureGroupDetailSnapshot? {
            if fail { throw ReadError.unavailable }
            return detail
        }
        func fetchPastures() throws -> [PastureSummary] { [] }
    }
}
