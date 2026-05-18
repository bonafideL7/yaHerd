//
//  ICloudAccountStatus.swift
//  yaHerd
//

import Foundation

enum ICloudUnavailableReason: Equatable {
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
    case unknown(String)

    var message: String {
        switch self {
        case .noAccount:
            "Sign in to iCloud on this device before enabling sync."
        case .restricted:
            "iCloud is restricted on this device. Check Screen Time, parental controls, or device management settings."
        case .couldNotDetermine:
            "yaHerd could not determine iCloud account status."
        case .temporarilyUnavailable:
            "iCloud is temporarily unavailable. Try again later."
        case .unknown(let message):
            message
        }
    }
}

enum ICloudAccountStatus: Equatable {
    case available
    case unavailable(ICloudUnavailableReason)
}
