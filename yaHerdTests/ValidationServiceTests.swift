import XCTest
@testable import yaHerd

final class ValidationServiceTests: XCTestCase {
    func testValidateAnimalRejectsSelfParent() {
        let animalID = UUID()

        XCTAssertThrowsError(
            try ValidationService.validateAnimal(
                ValidationService.AnimalValidationRules(
                    birthDate: .distantPast,
                    status: .active,
                    saleDate: nil,
                    deathDate: nil,
                    animalID: animalID,
                    sireID: animalID,
                    sireSex: .male,
                    damID: nil,
                    damSex: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? AnimalValidationError, .invalidParentSelection)
        }
    }

    func testValidateAnimalRejectsDuplicateParents() {
        let parentID = UUID()

        XCTAssertThrowsError(
            try ValidationService.validateAnimal(
                ValidationService.AnimalValidationRules(
                    birthDate: .distantPast,
                    status: .active,
                    saleDate: nil,
                    deathDate: nil,
                    animalID: UUID(),
                    sireID: parentID,
                    sireSex: .male,
                    damID: parentID,
                    damSex: .female
                )
            )
        ) { error in
            XCTAssertEqual(error as? AnimalValidationError, .duplicateParentSelection)
        }
    }

    func testValidateAnimalRejectsIncorrectSireSex() {
        XCTAssertThrowsError(
            try ValidationService.validateAnimal(
                ValidationService.AnimalValidationRules(
                    birthDate: .distantPast,
                    status: .active,
                    saleDate: nil,
                    deathDate: nil,
                    animalID: UUID(),
                    sireID: UUID(),
                    sireSex: .female,
                    damID: nil,
                    damSex: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? AnimalValidationError, .parentSexMismatch(expected: .male))
        }
    }

    func testValidateAnimalRequiresSaleDateForSoldStatus() {
        XCTAssertThrowsError(
            try ValidationService.validateAnimal(
                ValidationService.AnimalValidationRules(
                    birthDate: .distantPast,
                    status: .sold,
                    saleDate: nil,
                    deathDate: nil,
                    animalID: UUID(),
                    sireID: nil,
                    sireSex: nil,
                    damID: nil,
                    damSex: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? AnimalValidationError, .missingStatusDate)
        }
    }

    func testValidateAnimalRejectsStatusDateEarlierThanBirthDate() {
        let birthDate = Calendar.current.date(from: DateComponents(year: 2025, month: 5, day: 1))!
        let deathDate = Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 1))!

        XCTAssertThrowsError(
            try ValidationService.validateAnimal(
                ValidationService.AnimalValidationRules(
                    birthDate: birthDate,
                    status: .dead,
                    saleDate: nil,
                    deathDate: deathDate,
                    animalID: UUID(),
                    sireID: nil,
                    sireSex: nil,
                    damID: nil,
                    damSex: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? AnimalValidationError, .invalidStatusDate)
        }
    }
}
