//
//  CloudKitShareAppDelegate.swift
//  yaHerd
//

import CloudKit
import Foundation
import UIKit

extension Notification.Name {
    static let yaHerdCloudKitShareAccepted = Notification.Name("yaHerdCloudKitShareAccepted")
}

enum CloudKitShareNotificationUserInfoKey {
    static let metadata = "metadata"
}

final class CloudKitShareAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        NotificationCenter.default.post(
            name: .yaHerdCloudKitShareAccepted,
            object: self,
            userInfo: [CloudKitShareNotificationUserInfoKey.metadata: cloudKitShareMetadata]
        )
    }
}
