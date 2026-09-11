import Foundation
import SwiftData
import Testing
@testable import yaHerd

@Suite("Recovery mode release invariants")
struct RecoveryModeReleaseTests {
    @Test("Recovery container is ephemeral and configured read-only")
    @MainActor
    func recoveryContainerIsEphemeralAndReadOnly() throws {
        let container = try ModelContainerFactory.makeRecoveryContainer()
        let configuration = try #require(container.configurations.first)

        #expect(container.configurations.count == 1)
        #expect(configuration.isStoredInMemoryOnly)
        #expect(!configuration.allowsSave)
    }

    @Test("Recovery write policy rejects every application mutation category")
    @MainActor
    func recoveryWritePolicyRejectsEveryMutationCategory() throws {
        let suiteName = "RecoveryModeReleaseTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suiteName).journal.json")
        defer {
            try? FileManager.default.removeItem(at: journalURL)
            try? FileManager.default.removeItem(at: journalURL.appendingPathExtension("recovery"))
            try? FileManager.default.removeItem(at: journalURL.appendingPathExtension("verified-recovery"))
        }

        let policy = HerdCollaborationWritePolicy(
            dataAccessMode: .recoveryReadOnly,
            mutationGate: HerdDataMutationGate(
                defaults: defaults,
                journalFileURL: journalURL
            )
        )
        let reasons: [SharedDataMutationReason] = [
            .herd,
            .animal,
            .pasture,
            .dashboard,
            .fieldCheck,
            .working,
            .tagColor,
            .sampleData,
        ]

        for reason in reasons {
            do {
                try policy.validateCanWrite(reason: reason)
                Issue.record("Recovery mode unexpectedly allowed \(reason.displayName) mutation")
            } catch let error as HerdCollaborationWritePolicyError {
                #expect(error == .recoveryModeReadOnly(reason: reason))
            } catch {
                Issue.record("Unexpected recovery write-policy error for \(reason.displayName): \(error)")
            }
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
