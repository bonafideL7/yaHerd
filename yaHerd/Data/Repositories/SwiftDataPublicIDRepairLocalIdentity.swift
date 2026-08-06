import Foundation

/// Distinguishes related herd objects within one loaded SwiftData context.
/// This identity is used only to scope scalar-reference analysis during a repair run;
/// it is never included in canonical ordering, reports, backups, or replacement-ID seeds.
func stableRecordIdentifier(_ herd: Herd) -> ObjectIdentifier {
    ObjectIdentifier(herd)
}
