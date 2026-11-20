import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class TagColorSettingsHerdIsolationTests: XCTestCase {
    func testObsoleteTagColorSettingsCannotWriteAfterHerdChange() throws {
        for change in SelectionChange.allCases {
            for action in TagColorAction.allCases {
                let herdID = UUID()
                let selection = AppCurrentHerdSelection(currentHerdID: herdID)
                let origin = try XCTUnwrap(TagColorSettingsMutationGuard(selection: selection))
                let repository = TagColorSettingsWriteProbe()
                let library = TagColorLibraryStore(repository: repository)

                change.apply(to: selection, originalHerdID: herdID)

                let attempted: Void? = origin.performIfCurrent(in: selection) {
                    action.apply(to: library)
                }

                XCTAssertNil(attempted, "\(action) must not run after \(change)")
                XCTAssertEqual(repository.mutationCount, 0)
            }
        }
    }

    func testCurrentTagColorSettingsCanStillMutateAndNoOpSelectionDoesNotInvalidate() throws {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let origin = try XCTUnwrap(TagColorSettingsMutationGuard(selection: selection))
        let repository = TagColorSettingsWriteProbe()
        let library = TagColorLibraryStore(repository: repository)

        selection.select(herdID)

        for action in TagColorAction.allCases {
            let attempted: Void? = origin.performIfCurrent(in: selection) {
                action.apply(to: library)
            }
            XCTAssertNotNil(attempted)
        }

        XCTAssertEqual(repository.mutationCount, TagColorAction.allCases.count)
    }

    func testMutationGuardRequiresAnInitiallySelectedHerd() {
        XCTAssertNil(TagColorSettingsMutationGuard(selection: AppCurrentHerdSelection()))
    }
}

@MainActor
private enum SelectionChange: CaseIterable {
    case anotherHerd
    case returnToOriginal
    case revoked

    func apply(to selection: AppCurrentHerdSelection, originalHerdID: UUID) {
        switch self {
        case .anotherHerd:
            selection.select(UUID())
        case .returnToOriginal:
            selection.select(UUID())
            selection.select(originalHerdID)
        case .revoked:
            selection.select(nil)
        }
    }
}

@MainActor
private enum TagColorAction: CaseIterable {
    case save
    case setDefault
    case delete
    case reorder
    case restoreDefaults

    func apply(to library: TagColorLibraryStore) {
        switch self {
        case .save:
            _ = library.upsert(TagColorSnapshot(
                id: UUID(), name: "New Color", prefix: "NC",
                rgba: RGBAColor(r: 0.4, g: 0.6, b: 0.2)
            ))
        case .setDefault:
            _ = library.setDefaultColor(id: TagColorDefaults.whiteID)
        case .delete:
            library.delete(at: IndexSet(integer: 0))
        case .reorder:
            library.move(from: IndexSet(integer: 0), to: 1)
        case .restoreDefaults:
            library.restoreDefaultColors()
        }
    }
}

@MainActor
private final class TagColorSettingsWriteProbe: TagColorRepository {
    private(set) var mutationCount = 0

    func fetchColors() throws -> [TagColorSnapshot] {
        [TagColorSnapshot(
            id: TagColorDefaults.whiteID, name: "White", prefix: "W",
            rgba: RGBAColor(r: 1, g: 1, b: 1), isDefault: true
        )]
    }

    func fetchColor(id: UUID) throws -> TagColorSnapshot? { nil }
    func upsert(_ color: TagColorSnapshot) throws { mutationCount += 1 }
    func setDefaultColor(id: UUID) throws { mutationCount += 1 }
    func deleteColors(ids: [UUID]) throws { mutationCount += 1 }
    func reorder(colorIDs: [UUID]) throws { mutationCount += 1 }
    func restoreDefaultColors() throws { mutationCount += 1 }
}
