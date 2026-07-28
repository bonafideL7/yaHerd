# Application navigation

## Ownership

`AppNavigationState` is the application-scoped navigation model. It owns:

- the selected tab
- `HerdRouter`
- `WorkflowRouter`
- the currently presented app sheet
- the currently presented full-screen workflow

`MainTabView` only composes feature roots. It does not own navigation paths, search/filter state, modal booleans, or workflow continuation state.

## Typed routes

The navigation boundary uses Codable route values:

- `HerdRoute`
  - animal detail
  - pasture detail
  - field-check lists
  - working-session history
- `WorkflowRoute`
  - field-check list
  - field-check session, including a focused finding
  - working-session list
  - working-session detail
- `AppNavigationRequest`
  - neutral input for deep links, notifications, widgets, shortcuts, and tests

A new route must remain `Hashable` and `Codable`, and it must be represented in `AppNavigationSnapshot` when it affects restoration.

## Restoration

`RootAppView` stores the current `AppNavigationSnapshot` in scene storage under `navigation.restoration.v1`. The snapshot is versioned. Unknown versions are ignored rather than partially restored.

The restored state includes:

- selected tab
- herd route path
- herd mode, search, sort, and filters
- active workflow route
- app sheet
- full-screen workflow

## Deep links

The app registers the `yaherd` URL scheme.

Supported routes:

- `yaherd://animal/<animal UUID>`
- `yaherd://pasture/<pasture UUID>`
- `yaherd://field-check/<session UUID>`
- `yaherd://field-check/<session UUID>?finding=<finding UUID>`
- `yaherd://work-session/<session UUID>`
- `yaherd://search?q=<query>`

Invalid UUIDs and unknown destinations are rejected without mutating navigation state.

## Search ownership

Search remains a permanent tab-bar destination. The Search and YaHerd tabs use the same `HerdRouter`, search text, sort order, filters, and typed herd routes so search state is not duplicated. Selecting Search always opens the animal hierarchy and presents the search field; opening a result stays in the Search tab.

## Notification routing

App-level notification handlers may post `.yaHerdNavigationRequest` with an `AppNavigationRequest` as the notification object. `RootAppView` routes it through the same navigation model used by URLs and in-app actions.
