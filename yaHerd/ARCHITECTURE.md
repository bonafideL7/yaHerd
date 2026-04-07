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

## Pasture reference implementation

The pasture flow is the first fully separated slice:

- `Domain/Entities/*Pasture*`
- `Domain/Repositories/PastureRepository.swift`
- `Domain/UseCases/*Pasture*`
- `Data/Repositories/SwiftDataPastureRepository.swift`
- `Presentation/ViewModels/*Pasture*`
- `Presentation/Views/Pasture/*`

## Animal reference implementation

The animal list/add/detail flow now follows the same layered pattern:

- `Domain/Entities/*Animal*`
- `Domain/Repositories/AnimalRepository.swift`
- `Domain/UseCases/*Animal*`
- `Data/Repositories/SwiftDataAnimalRepository.swift`
- `Presentation/ViewModels/*Animal*`
- `Presentation/Views/Animal/*`

## Dependency direction

- `Presentation` depends on `Domain`
- `Data` depends on `Domain`
- `Domain` does not depend on `Presentation` or `Data`
- `App` wires the layers together

## Migration path for the rest of the project

Move the remaining slices the same way:

1. create domain entities and repository protocols
2. add use cases for application actions
3. implement SwiftData repositories in `Data/Repositories`
4. move screen state out of views into `Presentation/ViewModels`
5. keep views thin and declarative
