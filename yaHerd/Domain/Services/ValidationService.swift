//
//  ValidationService.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import Foundation

struct ValidationService {

    struct AnimalValidationRules {
        let birthDate: Date
        let status: AnimalStatus
        let saleDate: Date?
        let deathDate: Date?
        let animalID: UUID?
        let sireID: UUID?
        let sireSex: Sex?
        let damID: UUID?
        let damSex: Sex?
    }

    // MARK: - Animal Validation
    static func validateAnimal(
        birthDate: Date
    ) throws {
        try validateAnimal(
            AnimalValidationRules(
                birthDate: birthDate,
                status: .active,
                saleDate: nil,
                deathDate: nil,
                animalID: nil,
                sireID: nil,
                sireSex: nil,
                damID: nil,
                damSex: nil
            )
        )
    }

    static func validateAnimal(_ rules: AnimalValidationRules) throws {
        if rules.birthDate > Date() {
            throw ValidationError("Birth date cannot be in the future.")
        }

        if let animalID = rules.animalID {
            if rules.sireID == animalID || rules.damID == animalID {
                throw AnimalValidationError.invalidParentSelection
            }
        }

        if let sireID = rules.sireID, let damID = rules.damID, sireID == damID {
            throw AnimalValidationError.duplicateParentSelection
        }

        if let sireSex = rules.sireSex, sireSex != .male {
            throw AnimalValidationError.parentSexMismatch(expected: .male)
        }

        if let damSex = rules.damSex, damSex != .female {
            throw AnimalValidationError.parentSexMismatch(expected: .female)
        }

        switch rules.status {
        case .active:
            break
        case .sold:
            guard let saleDate = rules.saleDate else {
                throw AnimalValidationError.missingStatusDate
            }
            if saleDate < rules.birthDate {
                throw AnimalValidationError.invalidStatusDate
            }
        case .dead:
            guard let deathDate = rules.deathDate else {
                throw AnimalValidationError.missingStatusDate
            }
            if deathDate < rules.birthDate {
                throw AnimalValidationError.invalidStatusDate
            }
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
