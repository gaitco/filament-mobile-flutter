![filament_mobile](https://raw.githubusercontent.com/gaitco/filament-mobile-flutter/main/art/banner.png)

# filament_mobile

Renders a Laravel Filament 5 panel as a native Flutter mobile admin, driven by
the JSON contract that `gait/filament-mobile` serves.

![How it works](https://raw.githubusercontent.com/gaitco/filament-mobile-flutter/main/art/diagram.png)

![Screens](https://raw.githubusercontent.com/gaitco/filament-mobile-flutter/main/art/showcase.png)

## Requirements

- **Flutter `>=3.44.0`** and Dart `^3.12.0`. A host on an older toolchain must
  upgrade before adding this package — `pubspec.lock`'s SDK constraint moves
  with it.
- Two runtime dependencies only: `flutter` and `equatable`.

## Wiring

A host implements `FilamentTransport` over its own HTTP client, and optionally
a `PanelStateBuilder` to render loading, empty and failure states with its own
widgets.

The default endpoint prefix is `/api/mobile-panel` — absolute, so it appends
correctly to a base URL with no trailing slash. A prefix that is a **whole
URL** (`https://api.example.com/mobile`) is passed through unchanged, for a
host whose HTTP client carries no base URL of its own.

### `FilamentStrings` defaults to English, silently

The write path added twelve strings — `save`, `saveFailed`, the four delete
and cancel strings, and the six client-side validation hints. Every one has an
English default, so a host that upgrades and changes nothing still compiles
and still runs — and shows English hints under server-translated labels.

This is sharper than it sounds, because a client hint **blocks the
submission**: when a required field is empty the request never leaves the
phone, so the server's already-translated 422 never arrives and English is the
only thing the user ever sees. Measured on the pilot panel — an Arabic-locale
Filament panel with 33 production resources.

## Reads throw, writes don't — read this before implementing `FilamentTransport`

`FilamentTransport.get()` throws on transport **or** HTTP failure: a 404, a
403, a timeout, all come out the same way, and the caller turns that into a
`PanelFailure`.

`post()`, `put()` and `delete()` are the opposite, deliberately. They throw
**only** on a transport failure — no socket, DNS, timeout. Every HTTP
response, including a 422, 403 or 404, comes back as a `FilamentResponse`
carrying `statusCode` and `body`. A 422's body is where a form's per-field
error messages live, and `get()`'s throw-everything contract has nowhere to
put them.

If your host implementation of `post`/`put`/`delete` throws on a non-2xx
status (the natural thing to do if you're wrapping `dio` or `http` and
following `get()`'s lead), you will silently turn every validation error into
a generic failure banner and the form's field messages never reach the user.
Check your client's "throw on error status" setting and disable it for these
three methods, or catch the HTTP-status exception yourself and rebuild a
`FilamentResponse` from it.

`RestResourceDataSource.create/update/destroy` turn that response into a
`WriteResult` — a sealed type (`WriteSuccess`, `WriteInvalid`, `WriteDenied`,
`WriteGone`, `WriteFailed`) so a caller's `switch` is exhaustive. Only a
genuine transport throw becomes `WriteFailed`; every HTTP status the server
can return is a named outcome instead.

**One 204 gotcha worth debugging up front:** a delete typically answers 204
with a stripped, empty body. Return `body: const {}` for it, not `null` and
not the result of blindly `jsonDecode`-ing an empty string — most JSON
decoders throw on `''`, and a client that lets that throw propagate turns a
genuine success into a `WriteFailed`. This is the kind of thing that gets
debugged for an hour the first time a delete button reports failure despite
the row actually being gone.

`ResourceDataSource.state()` re-evaluates a resource's form against values
typed but not yet submitted (POSTs to `/{resource}/state`) and has no
`WriteResult` to carry a denial or a 404 into — its contract is "the current
form", so it throws on a non-2xx exactly as `get()` does, rather than
degrading a permission error into a silently empty form.

## A 401 is not a broken server — `FilamentTransportException.statusCode`

`PanelViewState` has a fifth variant, `PanelUnauthenticated`, rendered by
`MaterialPanelStateBuilder` with a lock icon instead of the generic failure
column — telling a signed-out user they were signed out, not that the server
broke.

The host side of it takes **one line**: when a host's `FilamentTransport.get()`
implementation throws on a 401, set `statusCode: 401` on the
`FilamentTransportException` it throws —

```dart
throw FilamentTransportException(message, statusCode: 401);
```

— instead of `FilamentTransportException(message)`. The package's read-path
providers inspect `statusCode` and expose `isUnauthenticated` on a 401, and
`PanelIndexScreen`, `ResourceListScreen`, `ResourceViewScreen` and
`ResourceFormScreen`'s edit path all surface that as `PanelUnauthenticated`.
(`ResourceFormScreen`'s create path has nothing to read on load, so there is
no 401 to catch there; its `submit()` keeps a 401 inside the ordinary
save-failure banner rather than switching the whole screen — see
`ResourceFormProvider.submit()`'s doc comment for why.) `statusCode` is
**advisory and optional**, defaulting to `null`. A host that never sets it
never trips `isUnauthenticated`; every failure still lands on `PanelFailure`,
exactly as before this field existed.
