//
//  HerdMapper.swift
//  yaHerd
//

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
