//
//  ValidationService.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import Foundation

struct ValidationService {

    // MARK: - Animal Validation
    static func validateAnimal(
        birthDate: Date
    ) throws {
        // Birthdate cannot be in the future
        if birthDate > Date() {
            throw ValidationError("Birth date cannot be in the future.")
        }
    }


    // MARK: - Health Record Validation
    static func validateHealthRecord(
        treatment: String
    ) throws {
        guard !treatment.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError("Treatment description is required.")
        }
    }


    // MARK: - Pregnancy Check Validation
    static func validatePregCheck() throws {
        // Add rules later if needed:
        // Example: ensure date is not in the future
    }


    // For throwing human-readable errors
    struct ValidationError: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
