import SwiftUI

enum FieldCheckRosterFilter: String, CaseIterable, Identifiable {
    case all
    case remaining
    case flagged
    case missing
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .all:
            return "All"
        case .remaining:
            return "Remaining"
        case .flagged:
            return "Flagged"
        case .missing:
            return "Missing"
        }
    }
}

enum FieldCheckSessionPane: String, CaseIterable, Identifiable {
    case summary
    case roster
    case quickCount
    case findings
    case notes
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .summary:
            return "Summary"
        case .roster:
            return "Roster"
        case .quickCount:
            return "Quick Count"
        case .findings:
            return "Findings"
        case .notes:
            return "Notes"
        }
    }
    
    static let defaultPane: FieldCheckSessionPane = .roster
}

extension View {
    func applyFieldCheckNavigationSubtitle(_ subtitle: String) -> some View {
        self.navigationSubtitle(subtitle)
    }
}
