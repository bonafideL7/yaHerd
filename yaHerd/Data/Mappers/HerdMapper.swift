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
            updatedAt: updatedAt
        )
    }
}

extension CDHerd {
    func toSummary() -> HerdSummary {
        HerdSummary(
            publicID: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
