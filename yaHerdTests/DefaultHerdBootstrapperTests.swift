//
//  DefaultHerdBootstrapperTests.swift
//  yaHerdTests
//

import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class DefaultHerdBootstrapperTests: XCTestCase {
    func testEnsureDefaultHerdCreatesOneHerdAndScopesExistingRecords() throws {
        let schema = yaHerdApp.makeSchema()
        let configuration = ModelConfiguration(
            "DefaultHerdBootstrapperTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, migrationPlan: YaHerdMigrationPlan.self, configurations: [configuration])
        let context = container.mainContext

        let pasture = Pasture(name: "North")
        let animal = Animal(name: "Cow 1", tagNumber: "1", birthDate: .now, pasture: pasture)
        let tag = AnimalTag(number: "1", isPrimary: true, animal: animal)
        let healthRecord = HealthRecord(date: .now, treatment: "Pinkeye", animal: animal)
        let fieldCheck = FieldCheckSession(pastureNameSnapshot: "North", pasture: pasture)

        context.insert(pasture)
        context.insert(animal)
        context.insert(tag)
        context.insert(healthRecord)
        context.insert(fieldCheck)
        try context.save()

        try DefaultHerdBootstrapper.ensureDefaultHerd(in: context)

        let herds = try context.fetch(FetchDescriptor<Herd>())
        XCTAssertEqual(herds.count, 1)
        let herd = try XCTUnwrap(herds.first)
        XCTAssertEqual(herd.name, DefaultHerdBootstrapper.defaultHerdName)
        XCTAssertTrue(animal.herd === herd)
        XCTAssertTrue(pasture.herd === herd)
        XCTAssertTrue(tag.herd === herd)
        XCTAssertTrue(healthRecord.herd === herd)
        XCTAssertTrue(fieldCheck.herd === herd)

        try DefaultHerdBootstrapper.ensureDefaultHerd(in: context)

        let herdsAfterSecondRun = try context.fetch(FetchDescriptor<Herd>())
        XCTAssertEqual(herdsAfterSecondRun.count, 1)
    }
}
