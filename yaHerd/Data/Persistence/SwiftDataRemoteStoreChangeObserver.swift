import CoreData
import Foundation

/// Keeps SwiftData's underlying Core Data remote-store notification inside the persistence layer.
/// Higher layers receive only the persistence-neutral application mutation event emitted by the
/// assembly that owns this observer.
final class SwiftDataRemoteStoreChangeObserver {
    private var observerToken: NSObjectProtocol?

    init(onRemoteChange: @escaping @Sendable () -> Void) {
        observerToken = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { _ in
            onRemoteChange()
        }
    }

    deinit {
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }
}
