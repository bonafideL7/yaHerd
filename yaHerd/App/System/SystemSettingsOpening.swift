//
//  SystemSettingsOpening.swift
//  yaHerd
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol SystemSettingsOpening {
    @MainActor
    func openSettings()
}

struct SystemSettingsOpener: SystemSettingsOpening {
    @MainActor
    func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
        #endif
    }
}
