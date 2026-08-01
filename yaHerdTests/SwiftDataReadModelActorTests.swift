import Foundation
import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class SwiftDataReadModelActorTests: XCTestCase {
    func testAnimalSummaryPagesAreBoundedAndOrdered() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        for index in 0..<260 {
            context.insert(
                Animal(
                    name: "Animal \(index)",
                    tagNumber: String(format: "%04d", index),
                    birthDate: .now,
                    status: .active,
                    sex: index.isMultiple(of: 2) ? .female : .male
                )
            )
        }
        try context.save()

        let reader = SwiftDataReadModelActor(modelContainer: container)
        let firstPage = try await reader.fetchAnimalSummaryPage(
            ReadPageRequest(offset: 0, limit: 250)
        )
        let secondPage = try await reader.fetchAnimalSummaryPage(
            ReadPageRequest(offset: 250, limit: 250)
        )

        XCTAssertEqual(firstPage.animals.count, 250)
        XCTAssertTrue(firstPage.hasMore)
        XCTAssertEqual(firstPage.animals.first?.displayTagNumber, "0000")
        XCTAssertEqual(secondPage.animals.count, 10)
        XCTAssertFalse(secondPage.hasMore)
        XCTAssertEqual(secondPage.animals.first?.displayTagNumber, "0250")
    }

    func testAnimalPastureOptionsReturnEveryPastureAcrossPages() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        for index in 0..<620 {
            context.insert(
                Pasture(name: String(format: "Pasture %04d", index))
            )
        }
        try context.save()

        let reader = SwiftDataReadModelActor(modelContainer: container)
        let options = try await reader.fetchAnimalPastureOptions(limit: 250)

        XCTAssertEqual(options.count, 620)
        XCTAssertEqual(options.first?.name, "Pasture 0000")
        XCTAssertEqual(options.last?.name, "Pasture 0619")
    }

    func testHomeFieldCheckRecordsPreserveWarningsAndExactFindingCountBeyondFormerLimits() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date.now

        for index in 0..<260 {
            context.insert(
                FieldCheckSession(
                    startedAt: now.addingTimeInterval(Double(-index * 60)),
                    completedAt: now,
                    pastureNameSnapshot: "Completed \(index)"
                )
            )
        }

        let warningSession = FieldCheckSession(
            startedAt: now.addingTimeInterval(-100_000),
            completedAt: now,
            pastureNameSnapshot: "Older warning session"
        )
        let unfinishedSession = FieldCheckSession(
            startedAt: now.addingTimeInterval(-200_000),
            completedAt: nil,
            pastureNameSnapshot: "Older unfinished session"
        )
        context.insert(warningSession)
        context.insert(unfinishedSession)

        let animalID = UUID()
        let missingCheck = FieldCheckAnimalCheck(
            animalIDSnapshot: animalID,
            rosterTagNumber: "101",
            missingConfirmedAt: now,
            session: warningSession
        )
        context.insert(missingCheck)
        warningSession.animalChecks = [missingCheck]

        var findings: [FieldCheckFinding] = []
        for index in 0..<205 {
            let finding = FieldCheckFinding(
                recordedAt: now.addingTimeInterval(Double(-index)),
                type: .generalObservation,
                severity: .warning,
                status: .open,
                note: "Finding \(index)",
                animalIDSnapshot: index == 0 ? animalID : nil,
                pastureNameSnapshot: "Older warning session",
                sessionIDSnapshot: warningSession.publicID,
                session: warningSession
            )
            context.insert(finding)
            findings.append(finding)
        }
        warningSession.findings = findings
        try context.save()

        let reader = SwiftDataReadModelActor(modelContainer: container)
        let records = try await reader.fetchHomeFieldCheckRecords()

        XCTAssertEqual(records.openFindingCount, 205)
        XCTAssertTrue(records.openFindings.isEmpty)
        XCTAssertTrue(records.hasHistory)
        XCTAssertEqual(
            Set(records.sessions.map(\.id)),
            Set([warningSession.publicID, unfinishedSession.publicID])
        )

        let warningSummary = try XCTUnwrap(
            records.sessions.first(where: { $0.id == warningSession.publicID })
        )
        XCTAssertEqual(warningSummary.flaggedAnimalCount, 1)
        XCTAssertEqual(warningSummary.missingAnimalCount, 1)
    }

    func testDashboardAnimalQueryUsesPredicateFriendlyRawValues() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let activePastureAnimal = Animal(
            name: "Pasture",
            tagNumber: "A1",
            birthDate: .now,
            status: .active,
            sex: .female
        )
        let workingPenAnimal = Animal(
            name: "Working",
            tagNumber: "A2",
            birthDate: .now,
            status: .active,
            sex: .female
        )
        workingPenAnimal.location = .workingPen
        let soldAnimal = Animal(
            name: "Sold",
            tagNumber: "A3",
            birthDate: .now,
            status: .sold,
            sex: .female
        )

        context.insert(activePastureAnimal)
        context.insert(workingPenAnimal)
        context.insert(soldAnimal)
        try context.save()

        let reader = SwiftDataReadModelActor(modelContainer: container)
        let active = try await reader.fetchDashboardAnimalRecords(kind: .active)
        let workingPen = try await reader.fetchDashboardAnimalRecords(kind: .workingPen)

        XCTAssertEqual(
            Set(active.map(\.id)),
            Set([activePastureAnimal.publicID, workingPenAnimal.publicID])
        )
        XCTAssertEqual(workingPen.map(\.id), [workingPenAnimal.publicID])
        XCTAssertEqual(soldAnimal.statusRawValue, AnimalStatus.sold.rawValue)
        XCTAssertEqual(workingPenAnimal.locationRawValue, AnimalLocation.workingPen.rawValue)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = yaHerdApp.makeSchema()
        let configuration = ModelConfiguration(
            "SwiftDataReadModelActorTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: YaHerdMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
