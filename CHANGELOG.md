# Changelog

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
