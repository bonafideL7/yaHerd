//
//  ICloudAvailabilityChecking.swift
//  yaHerd
//

import CloudKit

protocol ICloudAvailabilityChecking {
    func checkAvailability() async -> ICloudAccountStatus
}

struct ICloudAvailabilityChecker: ICloudAvailabilityChecking {
    func checkAvailability() async -> ICloudAccountStatus {
        do {
            let status = try await CKContainer.default().accountStatus()

            switch status {
            case .available:
                return .available

            case .noAccount:
                return .unavailable(.noAccount)

            case .restricted:
                return .unavailable(.restricted)

            case .couldNotDetermine:
                return .unavailable(.couldNotDetermine)

            case .temporarilyUnavailable:
                return .unavailable(.temporarilyUnavailable)

            @unknown default:
                return .unavailable(.couldNotDetermine)
            }
        } catch {
            return .unavailable(.unknown(error.localizedDescription))
        }
    }
}
