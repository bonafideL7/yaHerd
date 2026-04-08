import Foundation

enum DashboardRoute: Hashable {
    case animal(UUID)
    case pasture(UUID)
    case animalList(DashboardAnimalListKind)
    case pastureList
}
