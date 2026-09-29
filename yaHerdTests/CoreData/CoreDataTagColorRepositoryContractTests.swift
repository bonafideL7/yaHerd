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
        try TagColorRepositoryContract.assertUpsertNormalizesPersistsAndPreservesApplicationIdentity(using: fixture)
    }

    func testEmptyNameUpsertIsNoOp() async throws {
        let fixture = try await makeFixture()
        try TagColorRepositoryContract.assertEmptyNameUpsertIsNoOp(using: fixture)
    }

    func testDefaultSelectionIsExclusivePersistentAndUnaffectedByUnknownIDs() async throws {
        let fixture = try await makeFixture()
        try TagColorRepositoryContract.assertDefaultSelectionIsExclusivePersistentAndUnaffectedByUnknownIDs(using: fixture)
    }

    func testDeleteRemovesCustomColorsButBuiltInsRemainAvailableAndDefaultFallsBackToWhite() async throws {
        let fixture = try await makeFixture()
        try TagColorRepositoryContract.assertDeleteRemovesCustomColorsButBuiltInsRemainAvailableAndDefaultFallsBackToWhite(using: fixture)
    }

    func testReorderPersistsCompleteLibraryOrder() async throws {
        let fixture = try await makeFixture()
        try TagColorRepositoryContract.assertReorderPersistsCompleteLibraryOrder(using: fixture)
    }

    func testRestoreDefaultsRepairsCanonicalDefinitionsPreservesCustomsAndIsIdempotent() async throws {
        let fixture = try await makeFixture()
        try TagColorRepositoryContract.assertRestoreDefaultsRepairsCanonicalDefinitionsPreservesCustomsAndIsIdempotent(using: fixture)
    }

    func testNormalizedNameCollisionKeepsCanonicalIdentityAndRemapsReferences() async throws {
        let fixture = try await makeFixture()
        try TagColorRepositoryContract.assertNormalizedNameCollisionKeepsCanonicalIdentityAndRemapsReferences(using: fixture)
    }

    func testBuiltInNameCollisionPreservesBuiltInIdentityAndRemapsReferences() async throws {
        let fixture = try await makeFixture()
        try TagColorRepositoryContract.assertBuiltInNameCollisionPreservesBuiltInIdentityAndRemapsReferences(using: fixture)
    }


    func testReferencedCustomColorRemovalPreservesHistoricalReferenceIdentity() async throws {
        let fixture = try await makeFixture()
        try TagColorRepositoryContract.assertReferencedCustomColorRemovalPreservesHistoricalReferenceIdentity(using: fixture)
    }

    func testReadsWritesDefaultsAndNameUniquenessAreHerdScoped() async throws {
        let fixture = try await makeFixture()
        try TagColorRepositoryContract.assertReadsWritesDefaultsAndNameUniquenessAreHerdScoped(using: fixture)
    }

    func testMissingOrStaleCurrentHerdDoesNotFallbackOrBootstrapOnReadOrWrite() async throws {
        let fixture = try await makeFixture()
        try TagColorRepositoryContract.assertMissingOrStaleCurrentHerdDoesNotFallbackOrBootstrapOnReadOrWrite(using: fixture)
    }

    private func makeFixture() async throws -> TagColorRepositoryContractFixture {
        try await CoreDataTagColorContractHarness.make().fixture
    }
}
