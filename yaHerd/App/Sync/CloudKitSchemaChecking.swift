//
//  CloudKitSchemaChecking.swift
//  yaHerd
//

import CloudKit
import Foundation

struct CloudKitSchemaCheckResult: Equatable {
    let environmentDescription: String
    let passed: Bool
    let message: String
}

protocol CloudKitSchemaChecking {
    func runCheck() async -> CloudKitSchemaCheckResult
}

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
            let savedRecord = try await save(record, in: database)
            _ = try await fetch(recordID: savedRecord.recordID, in: database)
            try await delete(recordID: savedRecord.recordID, in: database)

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
        guard let environment = Bundle.main.object(forInfoDictionaryKey: "com.apple.developer.icloud-container-environment") as? String else {
            #if DEBUG
            return "Development (Debug build inferred)"
            #else
            return "Production (Release build inferred)"
            #endif
        }

        return environment
    }

    private func save(_ record: CKRecord, in database: CKDatabase) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    continuation.resume(throwing: CloudKitSchemaCheckError.missingSavedRecord)
                }
            }
        }
    }

    private func fetch(recordID: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: CloudKitSchemaCheckError.missingFetchedRecord)
                }
            }
        }
    }

    private func delete(recordID: CKRecord.ID, in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.delete(withRecordID: recordID) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
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

private enum CloudKitSchemaCheckError: LocalizedError {
    case missingSavedRecord
    case missingFetchedRecord

    var errorDescription: String? {
        switch self {
        case .missingSavedRecord:
            return "CloudKit did not return the saved diagnostic record."
        case .missingFetchedRecord:
            return "CloudKit did not return the fetched diagnostic record."
        }
    }
}
