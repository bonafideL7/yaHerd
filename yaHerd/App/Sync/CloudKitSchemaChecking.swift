//
//  CloudKitSchemaChecking.swift
//  yaHerd
//

import CloudKit
import Foundation

struct CloudKitSchemaCheckResult: Equatable, Sendable {
    let environmentDescription: String
    let passed: Bool
    let message: String
}

@MainActor
protocol CloudKitSchemaChecking {
    func runCheck() async -> CloudKitSchemaCheckResult
}

@MainActor
struct CloudKitSchemaChecker: CloudKitSchemaChecking {
    private let containerIdentifier: String

    init(containerIdentifier: String = ModelContainerFactory.cloudKitContainerIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    func runCheck() async -> CloudKitSchemaCheckResult {
        let environmentDescription = currentEnvironmentDescription()
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "yaHerd-schema-check-\(UUID().uuidString)")
        let record = CKRecord(recordType: "YHCloudKitSchemaDiagnostic", recordID: recordID)
        record["createdAt"] = Date() as CKRecordValue
        record["source"] = "yaHerd" as CKRecordValue

        do {
            let savedRecord = try await database.save(record)
            _ = try await database.record(for: savedRecord.recordID)
            _ = try await database.deleteRecord(withID: savedRecord.recordID)

            return CloudKitSchemaCheckResult(
                environmentDescription: environmentDescription,
                passed: true,
                message: "Passed. This build can write, read, and delete a diagnostic record in the active CloudKit environment."
            )
        } catch {
            return CloudKitSchemaCheckResult(
                environmentDescription: environmentDescription,
                passed: false,
                message: "Failed in \(environmentDescription): \(Self.describe(error))"
            )
        }
    }

    private func currentEnvironmentDescription() -> String {
        guard let environment = Bundle.main.object(
            forInfoDictionaryKey: "com.apple.developer.icloud-container-environment"
        ) as? String else {
            #if DEBUG
            return "Development (Debug build inferred)"
            #else
            return "Production (Release build inferred)"
            #endif
        }

        return environment
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = [nsError.localizedDescription]
        parts.append("Domain: \(nsError.domain)")
        parts.append("Code: \(nsError.code)")

        if let ckError = error as? CKError {
            parts.append("CloudKit: \(ckError.code)")
        }

        return parts.joined(separator: " | ")
    }
}
