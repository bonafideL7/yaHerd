import XCTest
@testable import yaHerd

@MainActor
final class CoreDataTagColorRepositoryContractTests: XCTestCase {
    func testBuiltInLibraryHasStableIdentityOrderingAndWhiteDefault() async throws {
        let fixture = try await makeFixture()
        try TagColorRepositoryContract.assertBuiltInLibraryHasStableIdentityOrderingAndWhiteDefault(using: fixture)
    }

    func testUpsertNormalizesPersistsAndPreservesApplicationIdentity() async throws {
        let fixture = try await makeFixture()
        try await TagColorRepositoryContract.assertUpsertNormalizesPersistsAndPreservesApplicationIdentity(using: fixture)
    }

    func testEmptyNameUpsertIsNoOp() async throws {
        let fixture = try await makeFixture()
        try await TagColorRepositoryContract.assertEmptyNameUpsertIsNoOp(using: fixture)
    }

    func testDefaultSelectionIsExclusivePersistentAndUnaffectedByUnknownIDs() async throws {
        let fixture = try await makeFixture()
        try await TagColorRepositoryContract.assertDefaultSelectionIsExclusivePersistentAndUnaffectedByUnknownIDs(using: fixture)
    }

    func testDeleteRemovesCustomColorsButBuiltInsRemainAvailableAndDefaultFallsBackToWhite() async throws {
        let fixture = try await makeFixture()
        try await TagColorRepositoryContract.assertDeleteRemovesCustomColorsButBuiltInsRemainAvailableAndDefaultFallsBackToWhite(using: fixture)
    }

    func testReorderPersistsCompleteLibraryOrder() async throws {
        let fixture = try await makeFixture()
        try await TagColorRepositoryContract.assertReorderPersistsCompleteLibraryOrder(using: fixture)
    }

    func testRestoreDefaultsRepairsCanonicalDefinitionsPreservesCustomsAndIsIdempotent() async throws {
        let fixture = try await makeFixture()
        try await TagColorRepositoryContract.assertRestoreDefaultsRepairsCanonicalDefinitionsPreservesCustomsAndIsIdempotent(using: fixture)
    }

    func testNormalizedNameCollisionKeepsCanonicalIdentityAndRemapsReferences() async throws {
        let fixture = try await makeFixture()
        try await TagColorRepositoryContract.assertNormalizedNameCollisionKeepsCanonicalIdentityAndRemapsReferences(using: fixture)
    }

    func testBuiltInNameCollisionPreservesBuiltInIdentityAndRemapsReferences() async throws {
        let fixture = try await makeFixture()
        try await TagColorRepositoryContract.assertBuiltInNameCollisionPreservesBuiltInIdentityAndRemapsReferences(using: fixture)
    }


    func testReferencedCustomColorRemovalPreservesHistoricalReferenceIdentity() async throws {
        let fixture = try await makeFixture()
        try await TagColorRepositoryContract.assertReferencedCustomColorRemovalPreservesHistoricalReferenceIdentity(using: fixture)
    }

    func testReadsWritesDefaultsAndNameUniquenessAreHerdScoped() async throws {
        let fixture = try await makeFixture()
        try await TagColorRepositoryContract.assertReadsWritesDefaultsAndNameUniquenessAreHerdScoped(using: fixture)
    }

    func testMissingOrStaleCurrentHerdDoesNotFallbackOrBootstrapOnReadOrWrite() async throws {
        let fixture = try await makeFixture()
        try await TagColorRepositoryContract.assertMissingOrStaleCurrentHerdDoesNotFallbackOrBootstrapOnReadOrWrite(using: fixture)
    }

    private func makeFixture() async throws -> TagColorRepositoryContractFixture {
        try await CoreDataTagColorContractHarness.make().fixture
    }
}
