import XCTest
import SwiftData
@testable import yaHerd

@MainActor
final class TagColorLibraryStoreTests: XCTestCase {
    func testDefaultColorStartsAsWhite() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)

        let store = TagColorLibraryStore(context: context)

        XCTAssertEqual(store.defaultColor.name, "White")
        XCTAssertEqual(store.resolvedColorID(nil), store.defaultColorID)
    }

    func testSetDefaultColorPersistsSingleDefault() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let store = TagColorLibraryStore(context: context)
        let blue = try XCTUnwrap(store.colors.first { $0.name == "Blue" })

        store.setDefaultColor(id: blue.id)

        XCTAssertEqual(store.defaultColor.id, blue.id)
        XCTAssertEqual(store.resolvedColorID(nil), blue.id)

        let persistedColors = try context.fetch(FetchDescriptor<TagColorDefinition>())
        XCTAssertEqual(persistedColors.filter { $0.isDefault }.count, 1)
        XCTAssertEqual(persistedColors.first(where: { $0.isDefault })?.id, blue.id)
    }


    func testSeedDefaultColorsExcludesRetiredTagColors() throws {
        let names = TagColorLibraryStore.seedDefaultColors().map(\.name)

        XCTAssertFalse(names.contains("Black"))
        XCTAssertFalse(names.contains("Brown"))
        XCTAssertFalse(names.contains("Gray"))
    }

    func testLoadRemovesRetiredDefaultTagColors() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let retiredColors = [
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D03")!, name: "Black", rgba: RGBAColor(r: 0, g: 0, b: 0)),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D0A")!, name: "Brown", rgba: RGBAColor(r: 0.55, g: 0.27, b: 0.07)),
            TagColorDefinition(id: UUID(uuidString: "4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D0B")!, name: "Gray", rgba: RGBAColor(r: 0.6, g: 0.6, b: 0.6))
        ]

        for color in retiredColors {
            context.insert(color)
        }
        context.insert(TagColorDefinition(name: "White", rgba: RGBAColor(r: 1, g: 1, b: 1), isDefault: true))
        try context.save()

        let store = TagColorLibraryStore(context: context)
        let names = store.colors.map(\.name)

        XCTAssertFalse(names.contains("Black"))
        XCTAssertFalse(names.contains("Brown"))
        XCTAssertFalse(names.contains("Gray"))
        XCTAssertEqual(store.defaultColor.name, "White")
    }


    func testLoadAppliesDefaultColorToTaggedAnimalsMissingColor() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let animal = Animal(name: "Cow 12", tagNumber: "12", tagColorID: nil, birthDate: .distantPast)
        context.insert(animal)
        try context.save()

        let store = TagColorLibraryStore(context: context)

        XCTAssertEqual(animal.tagColorID, store.defaultColorID)
    }
}
