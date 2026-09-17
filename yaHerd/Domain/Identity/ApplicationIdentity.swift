import Foundation

/// Stable identity assigned by yaHerd to a durable application entity.
///
/// This intentionally remains a semantic alias of `UUID`: Domain APIs stay independent of
/// persistence frameworks, and storage-native identifiers must never replace this value at
/// Domain or Presentation boundaries.
typealias ApplicationEntityID = UUID
