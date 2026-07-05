//
//  HerdSharingActionResult.swift
//  yaHerd
//

struct HerdSharingActionResult: Equatable {
    let title: String
    let message: String
    let systemShare: HerdSystemShare?

    init(
        title: String,
        message: String,
        systemShare: HerdSystemShare? = nil
    ) {
        self.title = title
        self.message = message
        self.systemShare = systemShare
    }

    static func == (lhs: HerdSharingActionResult, rhs: HerdSharingActionResult) -> Bool {
        lhs.title == rhs.title
            && lhs.message == rhs.message
            && (lhs.systemShare == nil) == (rhs.systemShare == nil)
    }
}
