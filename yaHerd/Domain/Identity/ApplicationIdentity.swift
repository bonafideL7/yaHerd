import Foundation

/// Stable identity assigned by yaHerd to a durable application entity.
///
/// This intentionally remains a semantic alias of `UUID`: Domain APIs stay independent of
/// persistence frameworks while Core Data can store the value directly as a UUID attribute.
/// `NSManagedObjectID`, CloudKit record identifiers, and other storage-native identifiers must
/// never replace this value at Domain or Presentation boundaries.
typealias ApplicationEntityID = UUID
