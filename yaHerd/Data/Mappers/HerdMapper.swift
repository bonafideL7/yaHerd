//
//  HerdMapper.swift
//  yaHerd
//

extension Herd {
    func toSummary() -> HerdSummary {
        HerdSummary(
            publicID: publicID,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            schemaVersion: schemaVersion
        )
    }
}
