import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class StartupMigrationRepairGateTests: XCTestCase {
    func testDefaultHerdBootstrapperDoesNotCreateOrRescopeRecordsWhileRepairIsPending() throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let journalURL = temporaryJournalURL()
        defer { try? FileManager.default.removeItem(at: journalURL.deletingLastPathComponent()) }

        let gate = try makePendingRepairGate(journalURL: journalURL)
        let migrationState = isolatedDefaults()

        try DefaultHerdBootstrapper.ensureDefaultHerdForAppLaunch(
            in: context,
            storageScope: "startup-repair-gate",
            migrationState: migrationState,
            mutationGate: gate
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<Herd>()).isEmpty)
    }

    func testFieldCheckSnapshotMigrationDoesNotRewritePublicIDReferencesWhileRepairIsPending() throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herd = Herd(name: "Migration gate", createdAt: timestamp, updatedAt: timestamp)
        context.insert(herd)
        let pasture = Pasture(name: "North")
        pasture.herd = herd
        context.insert(pasture)
        let session = FieldCheckSession(
            startedAt: timestamp,
            pastureNameSnapshot: "",
            pastureID: nil,
            pasture: pasture
        )
        session.herd = herd
        context.insert(session)
        try context.save()

        let journalURL = temporaryJournalURL()
        defer { try? FileManager.default.removeItem(at: journalURL.deletingLastPathComponent()) }
        let gate = try makePendingRepairGate(journalURL: journalURL)

        try FieldCheckHistoricalSnapshotMigrator.runIfNeeded(
            in: context,
            storageScope: "startup-repair-gate",
            migrationState: isolatedDefaults(),
            mutationGate: gate
        )

        XCTAssertEqual(session.pastureNameSnapshot, "")
        XCTAssertNil(session.pastureID)
    }

    private func makePendingRepairGate(journalURL: URL) throws -> HerdDataMutationGate {
        let gate = HerdDataMutationGate(
            defaults: isolatedDefaults(),
            journalFileURL: journalURL
        )
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try gate.requireLocalCommitCompletion(
            preparation: PublicIDRepairBridgePreparation(
                identity: .iCloud,
                herdPublicIDs: [UUID(uuidString: "91919191-9191-4191-8191-919191919191")!]
            ),
            report: PublicIDRepairReport(
                completedAt: timestamp,
                assessment: PublicIDRepairAssessment(scannedAt: timestamp, entities: []),
                replacements: [],
                referenceUpdates: [],
                backupFilename: "startup-gate.json",
                backupPath: "/tmp/startup-gate.json",
                validationIssueCount: 0
            ),
            resolutions: []
        )
        return gate
    }

    private func temporaryJournalURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "StartupMigrationRepairGateTests-\(UUID().uuidString)",
                isDirectory: true
            )
            .appendingPathComponent("PendingState.json")
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "StartupMigrationRepairGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
