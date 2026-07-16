import Foundation

extension Notification.Name {
    /// Post an `AppNavigationRequest` as the notification object to route from app-level notifications.
    static let yaHerdNavigationRequest = Notification.Name("yaHerd.navigation.request")
}
