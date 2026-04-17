# Clean Architecture layout

## Top-level layers

- `App/`
  - app bootstrap and app-scoped coordination
- `Domain/`
  - business rules, entities, repositories, use cases, domain services
- `Data/`
  - SwiftData models, repository implementations, seed/sample data
- `Presentation/`
  - SwiftUI views, screen models, presentation support types

## Dashboard reference implementation

The dashboard flow now follows the same layered split as the rest of the app:

- `Domain/Entities/Dashboard/*`
- `Domain/Repositories/DashboardRepository.swift`
- `Domain/UseCases/Dashboard/*`
- `Domain/Services/DashboardService.swift`
- `Data/Repositories/SwiftDataDashboardRepository.swift`
- `Presentation/ViewModels/Dashboard/*`
- `Presentation/Views/Dashboard/*`
- `App/Navigation/DashboardRoute.swift`

The dashboard UI is now a thin composition layer. Alert generation, overdue rules, stocking logic, list derivation, and snapshot assembly live in `Domain`.

## Pasture reference implementation

The pasture flow is separated as:

- `Domain/Entities/*Pasture*`
- `Domain/Repositories/PastureRepository.swift`
- `Domain/UseCases/*Pasture*`
- `Data/Repositories/SwiftDataPastureRepository.swift`
- `Presentation/ViewModels/*Pasture*`
- `Presentation/Views/Pasture/*`

## Animal reference implementation

The animal list/add/detail flow follows the same layered pattern:

- `Domain/Entities/*Animal*`
- `Domain/Repositories/AnimalRepository.swift`
- `Domain/UseCases/*Animal*`
- `Data/Repositories/SwiftDataAnimalRepository.swift`
- `Presentation/ViewModels/*Animal*`
- `Presentation/Views/Animal/*`


## Check reference implementation

The pasture check flow is separated as:

- `Domain/Entities/Check/*`
- `Domain/Repositories/FieldCheckRepository.swift`
- `Domain/UseCases/Check/*`
- `Data/Models/Check/*`
- `Data/Mappers/FieldCheckMapper.swift`
- `Data/Repositories/SwiftDataFieldCheckRepository.swift`
- `Presentation/ViewModels/Check/*`
- `Presentation/Views/Check/*`

Checks stay flexible by design: one session can mix head counts, tag-by-tag verification, findings, and newborn records without templates or type-specific modes.

## Dependency direction

- `Presentation` depends on `Domain`
- `Data` depends on `Domain`
- `Domain` does not depend on `Presentation` or `Data`
- `App` wires the layers together

## Rules for future growth

1. keep views declarative and state-light
2. move screen logic into presentation view models
3. put business rules and derivations in domain services and use cases
4. keep SwiftData access inside data repositories
5. keep navigation types in `App` or `Presentation`, never in `Data`
