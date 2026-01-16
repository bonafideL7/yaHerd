//
//  ValidationService.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import Foundation
import SwiftData

struct ValidationService {

    // MARK: - Animal Validation
    static func validateAnimal(
        tagNumber: String,
        birthDate: Date,
        context: ModelContext,
        existing: Animal? = nil
    ) throws {
        
        // Required field
        guard !tagNumber.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError("Tag number is required.")
        }

        // Tag numbers are reusable across time (sold/deceased animals may share the same tag).
        // Do NOT enforce global uniqueness.

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
