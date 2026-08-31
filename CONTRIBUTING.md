# Contributing

Thanks for helping! Two minutes of context before you start.

## How this repository works

Development happens in a private monorepo that holds this Flutter package,
the Laravel side, and their shared contract goldens. This repository is the
monorepo's public snapshot — the exact tree pub.dev serves — and CI runs
here on every push and pull request.

Pull requests are welcome. An accepted change is ported into the monorepo
with credit in the changelog and ships in the next release, so your PR may
be closed as "merged" without a merge commit — that is the normal flow, not
a rejection.

## What to work on

See **Status & roadmap** at the end of the README for the prioritized open
items, and the "deliberately out of scope" list of things not to propose.
For anything sizable, open an issue first so the approach is agreed before
you build it.

## Running the suite

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
dart analyze
flutter test
```

All three gates must pass — CI fails on an unformatted file or an analyzer
warning, not just on a red test.

## Ground rules

- **The core package ships exactly two dependencies: `flutter` and
  `equatable`.** A feature that needs a third-party package belongs in a
  companion package (the `filament_mobile_charts` / `filament_mobile_maps`
  model), wired in through `FieldRegistry`/`EntryRegistry`, never in core.
- **Never invent a capability the server did not declare.** An absent or
  wrong-typed contract key reads as the conservative default (disabled,
  read-only, empty) — a pre-upgrade server must keep working. Parsing never
  throws on unknown shapes.
- **`contract/*.json` are shared goldens** read by both this suite and the
  Laravel side's. Several carry deliberate deviations documented in the test
  that owns them — read the test's docblock before "fixing" a golden.
