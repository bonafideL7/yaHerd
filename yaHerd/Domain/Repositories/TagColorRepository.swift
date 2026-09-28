//
//  TagColorRepository.swift
//  yaHerd
//

import Foundation

@MainActor
protocol TagColorRepository: AnyObject {
    /// Returns the visible tag-color library for settings/editing surfaces.
    func fetchColors() throws -> [TagColorSnapshot]

    /// Resolves one tag-color definition by application UUID even when it is hidden from the
    /// visible library so historical tag/Field Check/Working snapshots can retain their display.
    ///
    /// Existing persistence implementations may use the default visible-library lookup. The target
    /// Core Data repository must override this when hidden definitions are persisted separately from
    /// the visible library.
    func fetchColor(id: UUID) throws -> TagColorSnapshot?

    func upsert(_ color: TagColorSnapshot) async throws
    func setDefaultColor(id: UUID) async throws
    func deleteColors(ids: [UUID]) async throws
    func reorder(colorIDs: [UUID]) async throws
    func restoreDefaultColors() async throws
}

extension TagColorRepository {
    func fetchColor(id: UUID) throws -> TagColorSnapshot? {
        try fetchColors().first { $0.id == id }
    }
}
