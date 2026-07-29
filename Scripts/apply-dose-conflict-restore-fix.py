from pathlib import Path

restoration = Path("yaHerd/Data/Sharing/CoreData/HerdSharingCoreDataStore+Restoration.swift")
text = restoration.read_text()
old = '''    case "quantity":
      if value.isNull {
        treatmentRecord.quantity = nil
      } else {
        guard let doubleValue = value.doubleValue else { return false }
        treatmentRecord.quantity = doubleValue
      }
'''
new = '''    case "quantity", "doseAmount":
      if value.isNull {
        treatmentRecord.doseAmount = nil
      } else {
        guard let doubleValue = value.doubleValue else { return false }
        treatmentRecord.doseAmount = doubleValue
      }
    case "doseUnit":
      if value.isNull {
        treatmentRecord.doseUnit = nil
      } else {
        guard
          let rawValue = value.stringValue,
          let doseUnit = WorkingTreatmentDoseUnit(rawValue: rawValue)
        else { return false }
        treatmentRecord.doseUnit = doseUnit
      }
    case "administrationRoute":
      if value.isNull {
        treatmentRecord.administrationRoute = nil
      } else {
        guard
          let rawValue = value.stringValue,
          let route = WorkingTreatmentAdministrationRoute(rawValue: rawValue)
        else { return false }
        treatmentRecord.administrationRoute = route
      }
'''
if text.count(old) != 1:
    raise SystemExit("Expected one legacy treatment quantity restore block")
restoration.write_text(text.replace(old, new))

conflict_review = Path("yaHerd/Domain/Entities/Herd/HerdSharingConflictReview.swift")
text = conflict_review.read_text()
old = '      return ["date", "itemName", "given", "quantity"]\n'
new = '''      return [
        "date", "itemName", "given", "quantity", "doseAmount", "doseUnit",
        "administrationRoute",
      ]
'''
if text.count(old) != 1:
    raise SystemExit("Expected one working treatment restore allowlist")
conflict_review.write_text(text.replace(old, new))

review_tests = Path("yaHerdTests/HerdSharingConflictReviewTests.swift")
text = review_tests.read_text()
old = '''        HerdSharingUpdatedRecordFieldChange(
          fieldName: "quantity",
          localValue: .double(2.0),
          sharedValue: .double(3.0)
        ),
'''
new = '''        HerdSharingUpdatedRecordFieldChange(
          fieldName: "doseAmount",
          localValue: .double(2.0),
          sharedValue: .double(3.0)
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "doseUnit",
          localValue: .string(WorkingTreatmentDoseUnit.milliliter.rawValue),
          sharedValue: .string(WorkingTreatmentDoseUnit.milligram.rawValue)
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "administrationRoute",
          localValue: .string(WorkingTreatmentAdministrationRoute.subcutaneous.rawValue),
          sharedValue: .string(WorkingTreatmentAdministrationRoute.intramuscular.rawValue)
        ),
'''
if text.count(old) != 1:
    raise SystemExit("Expected one legacy quantity conflict test block")
text = text.replace(old, new)
old = '    XCTAssertEqual(treatmentConflict.supportedLocalRestoreFieldChanges.map(\\.fieldName), ["quantity"])\n'
new = '''    XCTAssertEqual(
      treatmentConflict.supportedLocalRestoreFieldChanges.map(\\.fieldName),
      ["doseAmount", "doseUnit", "administrationRoute"]
    )
'''
if text.count(old) != 1:
    raise SystemExit("Expected one legacy quantity restore expectation")
review_tests.write_text(text.replace(old, new))

dose_tests = Path("yaHerdTests/HerdSharingTreatmentDoseModelTests.swift")
text = dose_tests.read_text()
marker = '''    private func makeSharedContext() throws -> NSManagedObjectContext {
'''
test = '''    func testRestoreLocalFieldsRestoresStructuredTreatmentDose() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        let session = WorkingSession(protocolName: "Working Session", protocolItems: [])
        let treatmentRecordID = UUID()
        let treatmentRecord = WorkingTreatmentRecord(
            publicID: treatmentRecordID,
            treatmentItemID: UUID(),
            itemName: "Vaccine A",
            given: true,
            dose: WorkingTreatmentDose(
                amount: 5,
                unit: .milligram,
                route: .intramuscular
            ),
            animal: animal,
            session: session
        )
        context.insert(animal)
        context.insert(session)
        context.insert(treatmentRecord)
        try context.save()

        let fieldChanges = [
            HerdSharingUpdatedRecordFieldChange(
                fieldName: "doseAmount",
                localValue: .double(2.5),
                sharedValue: .double(5)
            ),
            HerdSharingUpdatedRecordFieldChange(
                fieldName: "doseUnit",
                localValue: .string(WorkingTreatmentDoseUnit.milliliter.rawValue),
                sharedValue: .string(WorkingTreatmentDoseUnit.milligram.rawValue)
            ),
            HerdSharingUpdatedRecordFieldChange(
                fieldName: "administrationRoute",
                localValue: .string(WorkingTreatmentAdministrationRoute.subcutaneous.rawValue),
                sharedValue: .string(WorkingTreatmentAdministrationRoute.intramuscular.rawValue)
            ),
        ]
        let conflict = HerdSharingUpdatedRecordConflict(
            sourceEntityName: SharedWorkingTreatmentRecord.entityName,
            publicID: treatmentRecordID,
            localModifiedAt: Date(timeIntervalSince1970: 10),
            sharedModifiedAt: Date(timeIntervalSince1970: 20),
            fieldChanges: fieldChanges
        )
        let review = HerdSharingConflictReview(
            title: "Shared-data conflicts detected",
            sourceDescription: "Test import",
            detectedAt: Date(timeIntervalSince1970: 30),
            existingLocalRecordUpdateCount: 1,
            updatedRecordConflicts: [conflict],
            preventedDeleteConflicts: []
        )
        let selections = fieldChanges.map {
            HerdSharingLocalFieldRestoreSelection(
                sourceEntityName: SharedWorkingTreatmentRecord.entityName,
                publicID: treatmentRecordID,
                fieldName: $0.fieldName
            )
        }
        let storeDirectory = FileManager.default.temporaryDirectory
            .appending(path: "HerdSharingTreatmentDoseRestoreTests")
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let store = HerdSharingCoreDataStore(
            storeDirectoryURL: storeDirectory,
            journalFileURL: storeDirectory.appending(path: "journal.json")
        )

        let result = try store.restoreLocalFields(
            selections,
            from: review,
            context: context
        )

        XCTAssertEqual(result.requestedFieldCount, 3)
        XCTAssertEqual(result.restoredFieldCount, 3)
        XCTAssertEqual(result.skippedFieldCount, 0)
        XCTAssertEqual(treatmentRecord.doseAmount, 2.5)
        XCTAssertEqual(treatmentRecord.doseUnit, .milliliter)
        XCTAssertEqual(treatmentRecord.administrationRoute, .subcutaneous)
    }

'''
if text.count(marker) != 1:
    raise SystemExit("Expected one shared-context helper marker")
dose_tests.write_text(text.replace(marker, test + marker))
