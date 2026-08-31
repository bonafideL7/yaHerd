import Foundation

enum DraftRefreshPolicy {
    static func reconciledValue(
        draft: String,
        previouslyLoadedValue: String?,
        refreshedValue: String,
        isSameRecord: Bool,
        normalize: (String) -> String
    ) -> String {
        guard isSameRecord,
              let previouslyLoadedValue,
              normalize(draft) != normalize(previouslyLoadedValue)
        else {
            return refreshedValue
        }

        return draft
    }
}
