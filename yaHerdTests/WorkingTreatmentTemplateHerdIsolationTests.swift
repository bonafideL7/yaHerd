import XCTest
@testable import yaHerd

@MainActor
final class WorkingTreatmentTemplateHerdIsolationTests: XCTestCase {
    func testStaleTemplateMutationIsRejectedAfterHerdSwitchAndReturn() throws {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        var mutationCount = 0

        selection.select(UUID())
        let wrongHerdResult: Int? = WorkingTreatmentTemplateHerdAction.performIfCurrent(
            identity: identity,
            selection: selection
        ) {
            mutationCount += 1
            return mutationCount
        }
        XCTAssertNil(wrongHerdResult)

        selection.select(originalHerdID)
        let returnedHerdResult: Int? = WorkingTreatmentTemplateHerdAction.performIfCurrent(
            identity: identity,
            selection: selection
        ) {
            mutationCount += 1
            return mutationCount
        }
        XCTAssertNil(returnedHerdResult)
        XCTAssertEqual(mutationCount, 0, "An obsolete treatment-template draft must never mutate another selection.")
    }

    func testActiveHerdTemplateMutationExecutesExactlyOnce() throws {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        var mutationCount = 0

        let result: Int? = WorkingTreatmentTemplateHerdAction.performIfCurrent(
            identity: identity,
            selection: selection
        ) {
            mutationCount += 1
            return mutationCount
        }

        XCTAssertEqual(result, 1)
        XCTAssertEqual(mutationCount, 1)
    }

    func testMissingOrRevokedHerdIdentityBlocksTemplateMutation() throws {
        let selection = AppCurrentHerdSelection()
        var mutationCount = 0

        let unselected: Int? = WorkingTreatmentTemplateHerdAction.performIfCurrent(
            identity: nil,
            selection: selection
        ) {
            mutationCount += 1
            return mutationCount
        }
        XCTAssertNil(unselected)

        let herdID = UUID()
        selection.select(herdID)
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        selection.revalidateActiveHerd(from: [])

        let revoked: Int? = WorkingTreatmentTemplateHerdAction.performIfCurrent(
            identity: identity,
            selection: selection
        ) {
            mutationCount += 1
            return mutationCount
        }
        XCTAssertNil(revoked)
        XCTAssertEqual(mutationCount, 0)
    }

    func testTemplateListDoesNotExposePreviousHerdAfterSwitchOrRoundTrip() throws {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        let reader = TemplateListReaderProbe()
        reader.templates = [
            WorkingTreatmentTemplateSummary(id: UUID(), name: "Original Herd Treatment", treatmentCount: 1)
        ]
        let model = WorkingTreatmentTemplatesViewModel(repository: reader)
        model.load()

        XCTAssertEqual(model.visibleTemplates(identity: identity, selection: selection).count, 1)

        selection.select(UUID())
        XCTAssertTrue(model.visibleTemplates(identity: identity, selection: selection).isEmpty)

        selection.select(origin)
        XCTAssertTrue(model.visibleTemplates(identity: identity, selection: selection).isEmpty)

        model.clear()
        XCTAssertTrue(model.templates.isEmpty)

        let newIdentity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        reader.templates = [
            WorkingTreatmentTemplateSummary(id: UUID(), name: "Current Herd Treatment", treatmentCount: 2)
        ]
        model.load()
        XCTAssertEqual(
            model.visibleTemplates(identity: newIdentity, selection: selection).map(\.name),
            ["Current Herd Treatment"]
        )
    }

    func testTemplateDetailDoesNotExposePreviousHerdAfterSwitch() throws {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        let templateID = UUID()
        let reader = TemplateDetailReaderProbe(
            detail: WorkingTreatmentTemplateDetailSnapshot(
                id: templateID,
                name: "Original Herd Detail",
                plannedTreatments: [WorkingTreatmentPlanItem(name: "Vaccine")]
            )
        )
        let model = WorkingTreatmentTemplateDetailViewModel(
            templateID: templateID,
            repository: reader
        )
        model.load()
        XCTAssertEqual(model.visibleTemplate(identity: identity, selection: selection)?.name, "Original Herd Detail")

        selection.select(UUID())
        // Even if a delayed detail read completes under the newly selected
        // Herd, the original route must not adopt that Herd's template ID.
        model.load()
        XCTAssertNil(model.visibleTemplate(identity: identity, selection: selection))
        model.clear()
        XCTAssertNil(model.template)
    }

    func testTemplateListReadFailureIsNotAnEmptyHerdAndCanRetry() throws {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        let reader = TemplateListReaderProbe()
        let model = WorkingTreatmentTemplatesViewModel(repository: reader)

        reader.shouldFail = true
        model.load()
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.visibleTemplates(identity: identity, selection: selection).isEmpty)

        reader.shouldFail = false
        model.load()
        XCTAssertTrue(model.hasLoaded, "A successful empty query is not a failed import.")
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.templates.isEmpty)

        let existing = WorkingTreatmentTemplateSummary(
            id: UUID(), name: "Working Set", treatmentCount: 1
        )
        reader.templates = [existing]
        model.load()
        XCTAssertEqual(model.visibleTemplates(identity: identity, selection: selection).map(\.id), [existing.id])

        reader.shouldFail = true
        model.load()
        XCTAssertTrue(model.hasLoaded, "The last complete snapshot remains known.")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(
            model.visibleTemplates(identity: identity, selection: selection).isEmpty,
            "Failed refresh must not expose stale template choices."
        )

        reader.shouldFail = false
        model.load()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.visibleTemplates(identity: identity, selection: selection).map(\.id), [existing.id])
        model.clear()
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.errorMessage)
    }

    func testTemplateDetailSeparatesFailureFromNotFoundAndCanRetry() throws {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        let template = WorkingTreatmentTemplateDetailSnapshot(
            id: UUID(),
            name: "Recovery Treatment",
            plannedTreatments: [WorkingTreatmentPlanItem(name: "Vaccine")]
        )
        let reader = TemplateDetailReaderProbe(detail: template)
        let model = WorkingTreatmentTemplateDetailViewModel(
            templateID: template.id,
            repository: reader
        )

        reader.shouldFail = true
        model.load()
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.template)
        XCTAssertNotNil(model.errorMessage)

        reader.shouldFail = false
        reader.detail = nil
        model.load()
        XCTAssertTrue(model.hasLoaded, "Successful nil fetch means the template is absent.")
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.template)

        reader.detail = template
        model.load()
        XCTAssertEqual(model.visibleTemplate(identity: identity, selection: selection)?.id, template.id)

        reader.shouldFail = true
        model.load()
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(
            model.visibleTemplate(identity: identity, selection: selection),
            "An unavailable refresh must not expose a potentially stale editor."
        )

        reader.shouldFail = false
        model.load()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.visibleTemplate(identity: identity, selection: selection)?.name, template.name)
        model.clear()
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.template)
    }

}

@MainActor
private final class TemplateListReaderProbe: WorkingTreatmentTemplateListReader {
    var templates: [WorkingTreatmentTemplateSummary] = []
    var shouldFail = false

    func fetchTemplates() throws -> [WorkingTreatmentTemplateSummary] {
        if shouldFail { throw NSError(domain: "TemplateListRead", code: 1) }
        return templates
    }
}

@MainActor
private final class TemplateDetailReaderProbe: WorkingTreatmentTemplateDetailReader {
    var detail: WorkingTreatmentTemplateDetailSnapshot?
    var shouldFail = false

    init(detail: WorkingTreatmentTemplateDetailSnapshot) {
        self.detail = detail
    }

    func fetchTemplateDetail(id: UUID) throws -> WorkingTreatmentTemplateDetailSnapshot? {
        if shouldFail { throw NSError(domain: "TemplateDetailRead", code: 1) }
        return id == detail?.id ? detail : nil
    }
}
