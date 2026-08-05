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

A new route must remain `Hashable` and `Codable`. Only durable route state should be represented in `AppNavigationSnapshot`.

## Restoration

`RootAppView` stores the current `AppNavigationSnapshot` in scene storage under `navigation.restoration.v1`. The payload is versioned. The current decoder migrates the original version 1 payload and rejects unsupported future versions rather than partially restoring them.

The restored state includes:

- selected tab
- current herd identifier
- YaHerd and Search navigation paths
- herd mode, search, sort, and filters
- animal and pasture identifiers that still resolve in the current herd
- an active persisted field-check or working-session identifier

Restoration does not preserve app sheets, confirmation dialogs, temporary menus, unsaved creation forms, generic workflow list presentations, or transient workflow detail such as a focused finding.

Before restoring a record route, the app queries the corresponding repository. Missing animal and pasture destinations fall back to their existing list context. A full-screen field-check or working workflow is restored only when its session still exists and remains active. Missing, deleted, completed, finished, or cancelled sessions fall back to the relevant session list.

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

Search remains a permanent tab-bar destination. Search and YaHerd share the same herd mode, search text, sort order, filters, and other list criteria, matching the original feature. Each tab keeps its own typed navigation stack, so opening a Search result stays in Search without replacing the YaHerd tab's navigation state. Only the Search tab owns the system `.searchable` field. Selecting Search switches the shared herd mode to animals without automatically opening the keyboard; leaving Search dismisses keyboard focus. Dismissing Search clears the search and filters and returns to YaHerd.

## Notification routing

App-level notification handlers may post `.yaHerdNavigationRequest` with an `AppNavigationRequest` as the notification object. `RootAppView` routes it through the same navigation model used by URLs and in-app actions.
