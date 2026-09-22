import Foundation

/// Stable identity assigned by yaHerd to a durable application entity.
///
/// This intentionally remains a semantic alias of `UUID`: Domain APIs stay independent of
/// persistence frameworks, and storage-native identifiers must never replace this value at
/// Domain or Presentation boundaries.
///
/// Identity scope is supplied by the owning repository/aggregate rather than encoded in this alias.
/// `Herd` IDs are store-global; herd-owned IDs are interpreted within their owning/current Herd
/// unless a permanent feature contract explicitly defines broader semantics.
typealias ApplicationEntityID = UUID
