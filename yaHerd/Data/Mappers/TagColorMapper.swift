//
//  TagColorMapper.swift
//  yaHerd
//

extension CDTagColorDefinition {
    func toSnapshot() -> TagColorSnapshot {
        TagColorSnapshot(
            id: id,
            name: name,
            prefix: prefix,
            rgba: RGBAColor(
                r: red,
                g: green,
                b: blue,
                a: alpha
            ),
            sortOrder: Int(sortOrder),
            isDefault: isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
