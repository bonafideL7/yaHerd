import XCTest
@testable import yaHerd

final class DashboardMapperTests: XCTestCase {
    func testMakeAnimalRecordPreservesUnknownSexAndCalculatesExpectedCalvingDate() {
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: nil
        )
        
        let pregnancyCheckDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        
        let check = PregnancyCheck(
            date: pregnancyCheckDate,
            result: .pregnant,
            technician: nil,
            estimatedDaysPregnant: nil,
            dueDate: nil,
            sireAnimal: nil,
            workingSession: nil,
            animal: animal
        )
        
        animal.pregnancyChecks = [check]
        
        let record = DashboardMapper.makeAnimalRecord(from: animal)
        
        XCTAssertEqual(record.sex, Sex.unknown)
        XCTAssertEqual(record.lastPregnancyStatus, DashboardPregnancyStatus.pregnant)
        XCTAssertEqual(
            record.expectedCalvingDate,
            Calendar.current.date(byAdding: .day, value: 283, to: pregnancyCheckDate)
        )
    }

    func testMakeWorkingSessionRecordUsesStablePublicIDString() {
        let publicID = UUID()
        let session = WorkingSession(publicID: publicID, date: .distantPast, status: .active, sourcePasture: nil, protocolName: "Spring Work", protocolItems: [])

        let record = DashboardMapper.makeWorkingSessionRecord(from: session)

        XCTAssertEqual(record.id, publicID.uuidString)
        XCTAssertTrue(record.isActive)
    }
}
