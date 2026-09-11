import Foundation
import SwiftData
import Testing
@testable import yaHerd

@Suite("Recovery mode release invariants")
struct RecoveryModeReleaseTests {
    @Test("Recovery container rejects persistent saves")
    @MainActor
    func recoveryContainerRejectsPersistentSave() throws {
        let container = try ModelContainerFactory.makeRecoveryContainer()
        let context = container.mainContext
        context.insert(Herd(name: "Recovery Test Herd"))

        do {
            try context.save()
            Issue.record("Recovery ModelContext.save() unexpectedly succeeded")
        } catch {
            // Expected: recovery storage is configured with allowsSave = false.
        }
    }

    @Test("Recovery archive contains payload and terminal zero blocks")
    func recoveryArchiveContainsPayloadAndTerminalBlocks() throws {
        let payload = Data("diagnostics".utf8)
        let archive = try RecoveryTarArchiveBuilder.makeArchive(
            entries: [
                RecoveryArchiveEntry(
                    path: "RecoveryDiagnostics.json",
                    data: payload,
                    modifiedAt: Date(timeIntervalSince1970: 0)
                )
            ]
        )

        #expect(archive.count == 2048)
        #expect(archive.subdata(in: 512..<(512 + payload.count)) == payload)
        #expect(archive.suffix(1024).allSatisfy { $0 == 0 })
    }

    @Test("Recovery archive sanitizes traversal components")
    func recoveryArchiveSanitizesTraversalComponents() throws {
        let archive = try RecoveryTarArchiveBuilder.makeArchive(
            entries: [
                RecoveryArchiveEntry(
                    path: "../Storage/./yaHerd.sqlite",
                    data: Data([0x01]),
                    modifiedAt: Date(timeIntervalSince1970: 0)
                )
            ]
        )

        let nameBytes = archive.prefix(100).prefix { $0 != 0 }
        let storedName = String(decoding: nameBytes, as: UTF8.self)
        #expect(storedName == "Storage/yaHerd.sqlite")
    }

    @Test("Recovery archive rejects paths that exceed the TAR name field")
    func recoveryArchiveRejectsOverlongPath() {
        let path = String(repeating: "a", count: 101)

        do {
            _ = try RecoveryTarArchiveBuilder.makeArchive(
                entries: [RecoveryArchiveEntry(path: path, data: Data())]
            )
            Issue.record("Expected an overlong recovery archive path to be rejected")
        } catch let error as RecoveryArchiveError {
            #expect(error == .pathTooLong(path))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
