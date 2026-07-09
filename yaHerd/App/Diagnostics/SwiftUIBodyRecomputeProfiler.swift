import SwiftUI

struct SwiftUIBodyRecomputeProfiler: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        #if DEBUG
        let _ = PerformanceLog.event("SwiftUI body recomputed: \(name)")
        #endif
        return content
    }
}

extension View {
    func profileBodyRecomputation(_ name: String) -> some View {
        modifier(SwiftUIBodyRecomputeProfiler(name: name))
    }
}
