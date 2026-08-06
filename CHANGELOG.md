# Changelog

## 0.2.0 — 2026-08-06

- **Relation writes.** Server-side only — the write path already sent
  whatever the form's `disabled` flag said, so a relation field the server
  now publishes writable (`disabled: false`) is sent and synced correctly
  with no Dart code change. The contract test and golden fixture were
  updated to match the server's new shape.
- **Actions.** `ResourceRecord.actions` (`List<RecordAction>`, empty when
  the resource opted none in). New types `RecordAction` (`name`, `label`,
  `color?`, `icon?`, `confirmation?`) and `RecordActionConfirmation`
  (`heading`, `description?`, `submit`, `cancel`) in `data/record_action.dart`
  — note the name: `RecordActionConfirmation`, not `ActionConfirmation`,
  which was already taken by the unrelated schema-level action type in
  `schema/resource_action.dart`. New sealed `ActionResult`
  (`ActionSuccess`/`ActionFailed`) and `ResourceDataSource.runAction()` —
  a transport failure (no socket, DNS, timeout) comes back as
  `ActionFailed` carrying the host's message, the same contract as the
  writes, never an unhandled async error.
  `ResourceViewProvider.runAction()` runs an action and re-fetches on
  success. `ResourceViewScreen` renders a button per published action,
  confirms with the action's own strings when it carries a confirmation,
  and shows the server's message via the existing snack-bar convention.
  Three new `FilamentStrings`: `actionDone`, `actionFailed`,
  `actionConfirm` — English defaults, same rule as every other string.
  **New public surface:** `SemanticBadge.colorFor()` is now public, so
  action buttons reuse the card-badge colour map instead of a second one.

## 0.1.0 — 2026-08-06

Initial release.

- Panel index grouped by the server's navigation groups, with per-resource
  permission gating and an overridable empty state.
- Read path: resource list (card payloads, pagination, sorts) and record
  detail (infolist), skeleton-first rendering via `PanelStateBuilder`.
- Write path: create, edit and delete driven by the server's own form schema —
  labels, validation rules and translated messages come off the wire.
- Reactive forms: dependent selects re-settle against the server's
  `/state` endpoint; searchable relation options via `optionsUrl`.
- Transport is host-owned: implement `FilamentTransport` over your HTTP
  client; the package performs no HTTP and stores no tokens. A 401 surfaces
  as `PanelUnauthenticated` so the host can route to its own sign-in.
- Affordances follow the per-record permissions the panel publishes.

Not yet supported: relation writes (e.g. `Select::relationship()` pivot
sync), Filament actions, dashboard widgets.
