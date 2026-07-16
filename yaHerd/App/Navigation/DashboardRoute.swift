import Foundation

enum DashboardRoute: Hashable, Codable {
    case animal(UUID)
    case pasture(UUID)
    case animalList(DashboardAnimalListKind)
    case pastureList
}
