import XCTest
@testable import yaHerd

@MainActor
struct AnimalStatusReferenceRepositoryContractFixture {
    let makeReader: () -> any AnimalStatusReferenceReading
    let makeStatusReference: (_ name: String, _ baseStatus: AnimalStatus) throws -> AnimalStatusReferenceOption
}

@MainActor
enum AnimalStatusReferenceRepositoryContract {
    struct SeededReferences {
        let created: AnimalStatusReferenceOption
        let updated: AnimalStatusReferenceOption
    }

    @discardableResult
    static func assertOptionsPreserveIdentityNameAndBaseStatus(
        using fixture: AnimalStatusReferenceRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SeededReferences {
        let createdStatusReference = try fixture.makeStatusReference("Contract Deceased", .dead)
        let updatedStatusReference = try fixture.makeStatusReference("Contract Sold", .sold)

        let statusReferenceOptions = try fixture.makeReader().fetchStatusReferenceOptions()
        let reloadedCreatedStatusReference = try XCTUnwrap(
            statusReferenceOptions.first { $0.id == createdStatusReference.id },
            "The created status reference must be returned through the repository read API.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedCreatedStatusReference.name,
            createdStatusReference.name,
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedCreatedStatusReference.baseStatus.rawValue,
            AnimalStatus.dead.rawValue,
            "The dead status reference must retain its exact base status through the repository read API.",
            file: file,
            line: line
        )

        let reloadedUpdatedStatusReference = try XCTUnwrap(
            statusReferenceOptions.first { $0.id == updatedStatusReference.id },
            "The updated status reference must be returned through the repository read API.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedUpdatedStatusReference.name,
            updatedStatusReference.name,
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedUpdatedStatusReference.baseStatus.rawValue,
            AnimalStatus.sold.rawValue,
            "The sold status reference must retain its exact base status through the repository read API.",
            file: file,
            line: line
        )

        return SeededReferences(
            created: createdStatusReference,
            updated: updatedStatusReference
        )
    }
}
