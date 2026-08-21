# Changelog

## 0.9.2 — 2026-08-21

- **P17: translatable fields render as one field with locale chips,
  instead of a stacked field per locale.** `ResourceFormScreen`'s node walk
  groups consecutive-or-not `translatable: true` leaves sharing a dotted
  name's head into one field slot, with a chip row above it — one chip per
  locale, labelled by the uppercased locale code parsed off the field's own
  name, no `intl` dependency. Chips order by the new `ResourceSchema.locales`
  (propagated from `panel.locales` at parse time, the same way
  `ResourceSchema.direction` already is — no host wiring needed) when
  non-empty, else by appearance. Selecting a
  chip only changes which member renders — every locale's value stays in
  `FormValues` and the submitted payload still carries all of them, so
  submission logic is unchanged. A 422 keyed to a non-visible member
  force-switches the chip to it, matching the official web plugin's rule
  that an error must never hide behind a chip. A group of one locale
  renders chipless, exactly as today. Both `PanelSchema.locales` and
  `SchemaComponent.translatable` are tolerant of absence: an old server (no
  annotation) or an old client (annotation present but unread) both fall
  back to today's stacked-per-locale-field rendering, unchanged.

- sluggable panels work as-is; no client changes.

- **P14: medialibrary-backed fields and entries render for real.** A
  `SpatieMediaLibraryFileUpload` or `SpatieMediaLibraryImageEntry` field used
  to degrade to a bare uuid string, or nothing at all. `MediaItem`/`MediaSet`
  (`lib/schema/media_set.dart`) parse the flat `<field>.__media` sibling a
  medialibrary-backed field now publishes beside its raw value — one
  `{uuid, url, thumbUrl, name, size, mime}` entry per media item.
  `MediaSet.of(record, field)` is sibling-first, everywhere a media path can
  appear:
  - **Card leading image** (`resource_card.dart`) reads the sibling first,
    falling back to today's raw-string behaviour byte for byte when it is
    absent.
  - **`image_entry`** (`entry_registry.dart`) resolves through the sibling
    the same way, so `SpatieMediaLibraryImageEntry` actually renders instead
    of a blank tile.
  - **File field** (`field_widgets.dart`) shows the sibling's `name` (e.g.
    `photo.jpg`) instead of the raw uuid, with a small `thumbUrl` thumbnail
    leading each row when the server provides one. Value handling — a
    `List<String>` of opaque tokens, kept/removed/appended, `maxFiles`
    gating — is unchanged; a kept uuid and a freshly-uploaded path are both
    just opaque strings to the client.
  - A malformed or resolved-to-nothing item is dropped rather than failing
    the whole set; an absent sibling (old server, non-media field, or field
    simply not on the record) reads as "nothing to show", never an error.
  - **Testing**: `MediaSet`/`MediaItem` parse tests, sibling-present vs.
    absent card-leading and `image_entry` coverage, file-field name/thumbnail
    display, and a contract test (`test/media_record_contract_test.dart`)
    against the new `contract/media-record.json` golden.

- **P15: `SpatieTagsInput` support is server-side only** — it publishes as
  the existing `tags` node with the same `List<String>` wire value, so
  there is no client change to make.

## 0.9.1 — 2026-08-19

Packaging only — no code change, no API change. Adds `.pubignore` so the
mirror-only `art/` and `contract/` directories stay out of the published
archive. They exist only in the public mirror (`update-mirrors.sh` copies
`contract/` in for the mirror's CI and `art/` for the README images), and
publishing now runs FROM that mirror on a tag, so without this the archive
ships at 1 MB instead of 361 KB. `.pubignore` REPLACES `.gitignore` for
publishing rather than adding to it, so it repeats that file's entries —
dropping one would silently ship `build/` or `pubspec.lock`.

Also fixes `publish.yml`, which never worked: pub does not exchange the
GitHub OIDC token by itself, so the job blocked on an interactive browser
OAuth prompt instead of publishing. The workflow now trades the Actions
token for a pub.dev one and passes it as `PUB_TOKEN`.

## 0.9.0 — 2026-08-18

P10–P13 ship: the remaining field types, relation list search/sort,
multi-file upload, and date/time completeness. **Breaking for external
implementers of `ResourceDataSource`** — `relation()` gained optional
`search`/`sort`/`direction` named parameters (P11), so an implementation
that does not inherit the interface will not compile until it updates the
signature. Callers are unaffected; the transport ports are untouched.

- **Date/time steps are parsed, and deliberately not acted on.**
  `DateComponent` gains `hoursStep` / `minutesStep` / `secondsStep` — absent
  or wrong-typed reads as 1, the vendor default, the standing absence rule —
  but the widgets ignore them: the stock Material pickers have no step grid,
  the server enforces no step, and snapping a picked time would make mobile
  stricter than the web panel it mirrors. The keys exist for a host rendering
  its own picker. **No breaking changes, no new dependencies** — the package
  still ships exactly `flutter` + `equatable`. The server's final rejections
  stand client-side: no `disabledDates`, no `firstDayOfWeek`, bounds stay
  hints by web parity.

- **Multi-file upload renders and writes.** `FileComponent` gains
  `multiple` (absent or wrong-typed reads as `false`, the standing absence
  rule), `maxFiles`/`minFiles` (absent or wrong-typed reads as null), and
  its value is a `List<String>` of stored paths when `multiple` — a scalar
  arriving under a multiple field is tolerated on read, never coerced on
  write. `ResourceFormProvider._uploadedValue` appends the returned path
  for a multiple field instead of replacing, and
  `FileFieldWidget._buildMultiple` renders the current list as filename-
  basename rows with per-item remove plus an add button that stops being
  offered at `maxFiles` — a hint, the repeater-cap idiom: the server's
  array `max` is the rule. Each add tap is the single-file loop, unchanged:
  one pick through the host's `filePicker` (still a single `PickedFile`),
  one `uploadFile()` call, one append — the endpoint stays one file per
  request, so a multi-file field is N uploads, assembled client-side and
  submitted whole (wholesale-replacement; an empty list clears). All the
  single-file fallbacks carry over: no picker or no upload-capable
  transport and the field is read-only with the honest note, a
  server-published `readOnly` always wins, and the in-flight guard keeps a
  slow upload from being double-fired. The single-file path is
  byte-identical to before.

  **No breaking changes this time** — unlike the 0.8.x relation entries,
  nothing in `lib/ports/*` moved: `FilamentTransport`,
  `FilamentUploadTransport` and the `FilamentFilePicker`/`PickedFile`
  typedef are untouched, and a host on `RestResourceDataSource` needs no
  change. **No new dependencies** — the package still ships exactly
  `flutter` + `equatable`.

- **Relation lists gain search and sort.** `RelationDescriptor` now parses
  `search` (the resource level's `ResourceSearch`, reused) and `sorts`
  (`List<ResourceSort>`, reused), with a `defaultSort` getter — an absent or
  wrong-typed key reads as disabled / `[]`, never a throw: a pre-P11 server
  is indistinguishable from an undeclared relation, the standing absence
  rule. `RelationListProvider` gains `search()`/`sortBy()` mirroring
  `ResourceListProvider` exactly — the declared default sort is active from
  the first fetch, and every change refetches from page one — and
  `RelationListScreen` draws the search field and sort sheet gated on
  `relation.search.enabled` / `relation.sorts.isNotEmpty`, nothing drawn for
  an undeclared relation. `RelationSectionWidget` stays plain, deliberately:
  list controls live on the full screen.

  **Breaking for a host with its own `ResourceDataSource`
  implementation:** `relation()` gained three optional named parameters
  (`search`, `sort`, `direction`), so an external implementation will not
  compile until it updates the signature — the same class of break 0.8.0
  documented for the same interface. Source-compatible for callers; a host
  on `RestResourceDataSource` needs no change, and `lib/ports/*` stays
  untouched.

- **`toggle_buttons` and `slider` render.** `ToggleButtonsComponent` and
  `SliderComponent` join the `switch (type)` in `SchemaComponent.fromJson`,
  rendered by `ToggleButtonsFieldWidget` — a `ChoiceChip` per option, a
  `FilterChip` per option when `multiple` — and `SliderFieldWidget` — a
  Material `Slider`, or a `RangeSlider` when `multiple`, with divisions from
  the published `step`. Both widgets clamp rather than trust the payload,
  because both Material controls assert on contradictory bounds. **No new
  dependencies** — the package still ships exactly `flutter` + `equatable` —
  and **no new ports**: both types travel the existing
  `default`/`/state`/write paths. `slider` needs no slider-specific
  validation at all: the enforced bounds already arrive as the node's
  ordinary `rules`.

- **An entry-typed node in a form renders nothing.** The server's
  `Placeholder` publishes as `text_entry`; reaching a form it hits the field
  registry's existing `SizedBox.shrink()` arm — entries belong to infolists.
  That reading is now pinned.

- The contract suite pins both new shapes from `contract/panel.json`,
  including the absence readings: an absent or wrong-typed `multiple` reads
  as `false`, absent `options` as `[]`, absent `min`/`max` as `0`/`100`, and
  an absent `step` as no step constraint. `multiple` on a `slider` is a hint,
  never a gate — the documented server weakness (a range slider with no array
  default publishes `multiple: false` on `/schema`) is rendered from, never
  enforced against.

## 0.8.2 — 2026-08-13

Documentation and example only — no library code changed.

**The README shows the client now.** Its images predated 0.7.0's visual pass
over the same screens they pictured, so pub.dev advertised a UI that no longer
existed. Five screens recaptured, and three images added where they answer
something: the field-type gallery under "Field types this client renders", the
relation write flow under "Relations", and the dashboard under "Dashboard".

**The example can reach every screen.** `DEMO_SCREEN` gained `relations` and
`relation_form`, so P9's row writes — Add in the bar, edit and delete per row,
and the child resource's own form they open — are reachable without tapping
through; the demo's relation now publishes a `resource` key and a `reviews`
child resource, without which none of those controls exist to look at.
`DEMO_DIR=ltr` serves a left-to-right panel (the fixture stays Arabic by
default, since that is what exercises the direction wrap), and `DEMO_SCROLL`
opens a form already scrolled, which is how one form taller than a phone can
show all eleven of its field types.

Two demo defects went with it: the dashboard was rendered bare as `home:`,
without the host chrome `DashboardScreen` deliberately does not own, so it
painted onto black; and its scroll controller is now owned and disposed by the
State rather than built in `build()`.

## 0.8.1 — 2026-08-13

**A row's form no longer leaks its provider.** `RelationListScreen` built the
`ResourceFormProvider` for an Add or Edit inline in the route's `builder`, and
`ResourceFormScreen` does not own what it is handed — so nothing ever disposed
it. One leaked notifier per tap, and since `dispose()` is the only thing that
cancels the 400 ms `/state` debounce, backing out of a row's form just after
typing left a timer to fire a request against a provider nobody was listening
to. It is now built before the push and disposed in a `finally`, which also
fixes the quieter half of the bug: a route `builder` runs again on any rebuild,
so a fresh provider could have replaced the live one mid-edit.

**A relation section no longer races itself or blinks.**
`RelationSectionWidget` gained the drop-stale-response guard
`RelationListProvider` already had: the parent's listener fires on every one of
its reloads, so two quick pull-to-refreshes queued two fetches and whichever
answered LAST won rather than the one asked last — a section could settle on
older rows and keep them until something else reloaded. And a parent-triggered
refetch no longer flashes the rows to a spinner: with good rows already on
screen there is nothing worth blanking, so a section that was already correct
stops looking like a first load on every record reload. Derived from the status
rather than passed in per caller, so a future trigger cannot forget to ask.

## 0.8.0 — 2026-08-13

**Relation writes, against the matching Laravel 0.6.0.** A relation whose
descriptor carries a `resource` key — the server publishes one only when
exactly one registered resource owns the related model — is writable end to
end. `RelationDescriptor.resource` parses defensively: absent, null or
wrong-typed all read as *absent*, read-only, never a throw — the same
absence-means-unavailable rule `readOnly` already follows. Three members
join `ResourceDataSource` beside `relation()`:
`createRelation`/`updateRelation`/`deleteRelation`, with REST
implementations in `RestResourceDataSource` keyed off `relation.recordKey`
exactly as the read is. **This is a breaking change for a host with its own
`ResourceDataSource` implementation — it will not compile until it adds the
three methods.** A host on `RestResourceDataSource` needs no change; the
"member, not port" reasoning `relation()` itself shipped with applies, and
`lib/ports/*` stays untouched.

The form a relation row is edited in is the **child resource's own**
`ResourceFormScreen` — only the write target changes, through one small
value: `RelationSubmitTarget` (parent resource key, parent record id, the
relation) handed to the new `ResourceFormProvider.submitTarget`. Null —
every form outside a relation — submits exactly as before; non-null
redirects only the write, so validation, the `422` mapping and the error
banner are shared verbatim, which works because the server keys a relation
write's `422` by the same child-form field names the screen renders.
`RelationListScreen` takes an optional `childResource` and gates every
affordance off its published `permissions`: Add on `create`, per-row edit
and delete on `update`/`delete`, and a null `childResource` or a false flag
renders **no control at all** — absence, not disabled. The delete confirm
dialog mirrors `ResourceViewScreen`'s own, reusing the existing
`deleteConfirm*` strings. The per-row controls arrive through two new
general slots — `ResourceCard.trailing` and `PaginatedCardList.rowTrailing`
— rather than a relation-specific card fork. And `RelationSectionWidget`
takes an optional `parent` provider: the section now reloads when the
parent record finishes a reload, closing the stale-rows-after-an-action
weakness, and listens for a **success** notification only — a failed parent
reload leaves good rows on screen rather than blanking them behind the
parent's error.

**The one-sided rule-hint corner is closed.** This client has parsed
`rules.url`, `rules.regex` and `rules.confirmed` since the validator was
written; the Laravel package's 0.6.0 is the first server that publishes and
enforces them, so all eight client-side hints are finally live. `regex`
arrives **undelimited** (`^[a-z0-9_]+$`): `RegExp` takes a bare pattern and
would compile a PHP-delimited one into a pattern matching nothing — the `/` a
literal, the `^` behind it unreachable — so a `->regex()` field would be
unsubmittable for values the server accepts, and the fail-open path never
fires because such a pattern compiles cleanly. A pattern whose flags cannot
cross the wire arrives as no hint at all rather than a stricter one. A pattern
Dart genuinely cannot compile still fails open — the server revalidates
regardless. Two repeater fixes ride along:
`FieldState.searchOptionsFor` is the public, per-field variant of
`searchOptions` — a row's select renders off the item *template*, so its
remote-options lookup must bind to the child's own name, and handing the
repeater's closure down would query the wrong field — and `_validateRows`
now marks every validated row child **dirty**, because a synthetic row
`FormValues` cannot reconstruct the stored-vs-touched distinction the
top-level form relies on. The trade-off, stated in the README: an untouched
legacy colour value in a stored repeater row now blocks submission, where
before a malformed colour the user *just typed* into a row submitted
unchallenged. Over-eager on purpose, both ways.

**`BooleanBadge`.** A card's badge slot bound to a boolean column renders
Filament's boolean-column idiom — a check or a cross — instead of the
literal word `true`. The colour looks up `'true'/'false'` then `'1'/'0'`
(JSON object keys are strings; `true` as a PHP array key becomes `1`),
falling back to `success`/`gray`. Detection happens on the raw typed value
before stringifying, because after `toString()` a real bool and the string
`"true"` are indistinguishable — and the string must stay a text badge.

**Charts have a ready-made renderer.** The dashboard contract stays
"published, not drawn" in this package — the two-dependency promise
(`flutter` + `equatable`) is load-bearing — but the new sibling package
[`filament_mobile_charts`](https://pub.dev/packages/filament_mobile_charts)
is the opt-in other half: `flChartBuilder()` over fl_chart, every drawable
chart type, passed to the `chartBuilder` slot `DashboardScreen` already had.

A relationship repeater is editable against a current server — its save is
delete-all-then-recreate (keyless state; pinned server-side in
`RepeaterWriteTest`), which the Repeater section of the README now states
plainly. Against Laravel 0.6.0 the field also **prefills**: that server
publishes the rows in the record payload, so the widget seeds from them and
an edit to another field submits them back untouched. No client change was
needed for it — a relationship repeater now arrives in exactly the shape a
JSON-column repeater always did.

## 0.7.0 — 2026-08-08

**A latin sentence keeps its punctuation under RTL.** Reported from a real
simulator: an English review body inside an `ar` panel rendered
`.Great lamp, sturdy base` — the trailing full stop at the wrong end, because
a period is bidi-neutral and takes the paragraph's direction. The previous
release isolated grouped **digits** only, so a phone number rendered correctly
while the sentence around it did not. The rule now covers any run whose own
base direction opposes the paragraph's. Measured: `x(Great)=14.0 / x(.)=0.0`
before, `x(Great)=0.0 / x(.)=322.0` after.

A **composed** paragraph — rich text, built from several mark leaves — cannot
use that, because isolating each leaf changes how the whole paragraph lays out
(measured: a blockquote lost its RTL indent). Those paragraphs resolve their
own `textDirection` from their own content instead, so an English summary
inside an Arabic panel reads left to right while an Arabic sibling keeps RTL
with its phone number intact.

**The default screens got a visual pass.** They are a reference implementation
rather than a design system — a host still overrides any of it through
`PanelStateBuilder` and the registries — but the defaults were genuinely hard
to read:

- record actions move into an overflow menu. Inline they were coloured
  `TextButton`s of varying width wedged between two icon buttons — three
  treatments in one bar, crowding a phone and overflowing at three actions.
  The semantic colour survives as a leading dot. **A host calling these by
  label in a widget test now opens the menu first.**
- bare top-level entries are grouped into one card; a panel declaring
  `Section`s already got that treatment, one declaring bare entries did not.
- an entry label is muted and smaller, so it reads as a label rather than as
  a sibling line of its own value.
- `ResourceCard` is outlined rather than filled and carries its own margin —
  filled cards stacked with no gap read as a wall of slabs.
- the panel index gets outlined cards with divided rows and a chevron that
  **flips with the direction**: `ListTile` moves the slot under RTL, but the
  glyph has to be chosen, or it points back at the text it should lead away
  from.

**Colour and time fields.** `color` and `time` render and edit against the
matching Laravel release.

`color` is a **text field with a live swatch**, not a colour wheel — this
package takes no colour dependency, and a hand-rolled picker's colour maths is
easy to get subtly wrong and hard to test. It parses all four formats and
**never converts between them**: a field declared `rgb` emits `rgb`, never an
equivalent hex. A malformed value blocks submission, but **only once the user
has edited that field** — the client must not invent a constraint the server
does not have, and must not block a save over a value that was already in the
database when the form opened.

`time` joins `DateKind`, which is now a three-way. `DateComponent` gained
`seconds` and `unreadableBounds`, the latter distinguishing "no bound was
declared" from "a bound arrived that I could not parse"; the second is a
contract violation and warns in debug builds only.

**Three bugs fixed, all of which a host may have hit:**

- **A bounded date field crashed on tap.** `showDatePicker` asserts that
  `initialDate` lies within `firstDate`/`lastDate`, and the field passed the
  stored value through unclamped. Latent until this release started publishing
  bounds — before that every bound was null and the fallback range was
  1900–2100, so `initialDate` was always trivially in range. The clamp runs
  through `DateUtils.dateOnly`, because `showDatePicker` applies that itself
  *before* asserting, so an instant-wise clamp still trips where local time and
  UTC sit on different calendar days. Contradictory bounds (`min > max`) now
  read as no bounds instead of crashing.
- **Every datetime field showed a 12-hour clock to 24-hour users.**
  `formatTimeOfDay` never read `MediaQuery.alwaysUse24HourFormat`, so a
  24-hour-locale user saw `2:05 PM`.
- **A `seconds: true` field silently truncated stored seconds.** Opening the
  picker and pressing OK without editing turned `14:05:30` into `14:05:00`.
  Seconds are now preserved when the hour and minute are unchanged, and reset
  when the time genuinely changed — welding a stale `:30` onto a newly chosen
  16:20 would be a time the user never picked.

**Host-affecting:** `SchemaComponent` is `sealed`, so a host switching
exhaustively over component types *outside* `FieldRegistry` gains two more
cases. A host using `FieldRegistry` is unaffected.

## 0.6.0 — 2026-08-07

**Radio, tags and key/value.** Three new field types render and edit
correctly against the matching Laravel release.

`radio` parses onto the same `SelectComponent` model `select`/`multiselect`
already use (identical config shape — `config.options`), but renders through
a new, distinct `RadioFieldWidget`: one stacked `RadioListTile` per option,
single selection, honouring `state.enabled` and the server's `readOnly`.
Matched in `FieldRegistry.build()`'s `switch` before the bare
`SelectComponent()` case, since both patterns would otherwise match a radio
node. A `radio` node never carries `config.optionsUrl`, however many options
it has — see the Laravel README's Radio section for why.

`tags` parses into a new `TagsComponent` (`separator`, `suggestions`) and
renders through `TagsFieldWidget` — chips with a remove affordance, a text
field committing on submit, `suggestions` offered when published. The value
is always a `List<String>` in form state; `separator` is read for display
only, never built or parsed client-side. New string,
`FilamentStrings.tagHint` (`'Add a tag'`).

`keyvalue` parses into a new `KeyValueComponent` (`addable`, `deletable`,
`editableKeys`, `editableValues`, `keyLabel`, `valueLabel`,
`keyPlaceholder`, `valuePlaceholder`; all four booleans default `true` when
absent) and renders through `KeyValueFieldWidget`: one row per pair, Add
when `addable`, Remove per row when `deletable`. A row whose key or value
gate is off renders that cell as plain `Text`, never a disabled text field —
the affordance is absent, not disabled, same rule this package applies
everywhere else. Reuses the existing `FilamentStrings.addItem`/`.removeItem`
rather than adding new ones. **Rows carry identity independent of their
key** — `_pairs` is held as `List<MapEntry<String, String>>` state, seeded
once and mutated in place rather than re-derived from the map on every
build, fixed from a first cut where renaming a key into a transient
collision with another row's key merged the two rows, and adding two rows in
a row produced only one.

Known weaknesses, stated in the README: `Radio::isInline()`,
`splitKeys`/`tagPrefix`/`tagSuffix` are not on the wire; key/value has no
reordering, matching the repeater; all four key/value gates are client
hints — see the Laravel README's Key/value section for what "not enforced by
the write path" means and its contrast with `disabled`, which this package's
write path does enforce.

**Mostly no break for a host, with one exception for a very specific
shape.** `radio` reuses the existing `SelectComponent` — nothing new for a
host matching on component *class*. `TagsComponent` and `KeyValueComponent`
are new subtypes of the **sealed** `SchemaComponent` hierarchy: a host using
`FieldRegistry` (the documented extension point) is unaffected, since
`FieldRegistry.build()`'s own `switch` already has cases for both and a
host's custom `_builders` entry still takes priority. **A host that wrote
its own exhaustive `switch` directly over `SchemaComponent` — bypassing
`FieldRegistry` — will not compile until it adds a case for each new
subtype**, because a sealed hierarchy makes an unhandled case a compile
error rather than a silently-skipped one. `radio`/`tags`/`keyvalue` also
joined `FieldRegistry._builtInTypes`, which does not affect a host at all —
it is read-only, informational, derived alongside a host's own registered
types for `renderableTypes`.

## 0.5.1 — 2026-08-07

Documentation only. No code, no API and no dependency changed; `0.5.0` and
`0.5.1` are byte-identical in `lib/`.

The README was restructured to read as a landing page rather than a feature log
— each release had appended its own section, leaving the file ordered by ship
date and opening on a caveat before it said what the package does. It now leads
with **Install** and a **Quick start** (type-checked against the real API), then
a **What ships** table, then the same per-feature reference as before with
nothing removed. `FilamentTransport`'s two runtime surprises — reads throw while
writes do not, and a 401 is not a broken server — now sit under *Implementing
`FilamentTransport`*, where they apply.

Published as its own version because pub.dev renders the README from the
published archive: the improved page cannot reach pub.dev without one.

## 0.5.0 — 2026-08-07

**Upload.** A single-file `FileUpload` field is editable from the phone,
through a new **optional, additive** port, `FilamentUploadTransport` — a
separate interface from `FilamentTransport`, not a fifth method on it:
`FilamentTransport` is an `abstract interface class`, every host implements
it with `implements`, and `implements` inherits the interface without any
implementation, so adding a member — even one with a default body — is a
compile error in every existing host (verified against the analyzer,
`non_abstract_class_inherits_abstract_member`). A host that never uploads is
untouched; nothing about this release breaks an existing `FilamentTransport`
implementation. A host that wants uploads implements both interfaces and
gets a real multipart upload in about three statements — see the README's
Upload section for the example app's unedited implementation.
`ResourceDataSource.uploadFile()` returns a sealed `UploadResult` —
`UploadSuccess(path)` or `UploadFailed(message, {statusCode})` — mirroring
`ActionResult`; a host whose transport lacks the port gets an `UploadFailed`
naming what to implement, never a throw. `ResourceFormScreen` takes an
optional `filePicker` (`FilamentFilePicker` / `PickedFile`), the same
escape-hatch shape `chartBuilder` established for dashboard charts — the
README shows an `image_picker`-backed example. Without a picker, or without
a transport implementing the upload port, the field stays read-only with an
honest `filePickerUnavailable` note; `readOnly` published by the server
always wins over a host-supplied picker. Upload happens on pick, not on
save: the control shows `uploading` and disables itself for the duration, so
a slow upload cannot be double-fired. A `422` routes to the field's own
error, same as a write's per-field validation; every other failure routes to
the form's error banner. Five new `FilamentStrings`, all English-default:
`chooseFile`, `uploading`, `uploadFailed`, `filePickerUnavailable`,
`fileFieldReadOnly`. Known weaknesses, stated in the README: orphaned files
accumulate without host-side pruning, there is no upload progress
percentage (the port returns a future, not a stream), the whole file is
held in memory bounded only by the server-enforced `maxSize`, and
multi-file remains unusable. This is P6a — the first of P6's six
sub-projects. Final P6a review round: an upload whose result lands after
the provider is disposed — the user backed out of the form mid-upload — is
dropped instead of asserting on a disposed `ChangeNotifier` (the success
path used to notify unguarded; both failure paths were already guarded).

**Dashboard.** `DashboardProvider` + `DashboardScreen` render a Filament
panel's opted-in dashboard widgets, following the same provider/screen shape
as every other read path — `LoadStatus`, skeleton-first, pull-to-refresh,
`PanelUnauthenticated` on a 401 — with one deliberate omission:
`DashboardProvider` has no `needsAppUpdate`, because the dashboard carries
no contract version to be behind on.

`DashboardData` parses `GET /dashboard` into a list of sealed
`DashboardWidgetData` — `StatsWidgetData` (a row of `StatData` cards) and
`ChartWidgetData` (a labelled axis and one or more `ChartDataset`s) — so a
`switch` over a widget is exhaustive and a server that grows a widget kind
this build does not know degrades that entry rather than breaking the rest.

**Stat cards render fully, including a hand-drawn sparkline** —
`StatSparkline`, a `CustomPainter` polyline. It needs no dependency, so this
release still ships exactly two: `flutter`, `equatable`.

**Charts are published, not drawn.** `DashboardScreen` takes an optional
`chartBuilder` (`Widget Function(BuildContext, ChartWidgetData)`); without
one, a chart card renders its heading and the new `chartUnavailable` string
rather than a blank box. See the README's Dashboard section for a ten-line
`fl_chart` example.

**A refresh keeps the dashboard on screen.** While a reload is in flight
with data already loaded, `DashboardScreen` keeps rendering that data under
the `RefreshIndicator` instead of swapping the body — indicator included —
for a full-screen spinner mid-gesture. Only the true first load shows the
loading state.

`StatsWidgetData` now carries `description` beside `heading`, matching the
server's stats node (`StatsOverviewWidget::getDescription()`), symmetric
with `ChartWidgetData`.

Two new `FilamentStrings`, both English-default: `dashboardEmpty` ('Nothing
to show yet.') and `chartUnavailable` ('No chart renderer supplied.').

The wire is unchanged for every existing screen; this release only adds a
new endpoint's client.

**Offline schema cache.** Two new **optional, additive** ports —
`FilamentConditionalTransport` (`getConditional()`, a 304-aware GET) and
`FilamentSchemaCache` (`read`/`write`/`clear` a `CachedSchema`) — let
`/schema`'s document survive a restart and revalidate over a `304` instead
of a full refetch. Same reasoning as `FilamentUploadTransport`:
`FilamentConditionalTransport` is a second interface, not a new method on
`FilamentTransport`, because `implements` inherits no implementation and
adding a member there is a compile error in every existing host. **Neither
port breaks an existing `FilamentTransport` implementation** — both are
optional and additive, and without them behaviour is exactly today's:
in-memory only, a full document every time. `ResourceDataSource` is
different: it gained abstract `cachedPanel()` here, on top of the
`uploadFile()` added earlier in this same release, so **a host that
implements `ResourceDataSource` directly must add both members when
upgrading from 0.4.0** — the interface exists for exactly that
substitution, and it will not compile until both are there. Hosts on
`RestResourceDataSource` are unaffected. `PanelProvider.load()` now reads the
cache first: with a usable entry it publishes the cached panel immediately
(`status` goes straight to `success`, never `loading`) and revalidates
behind it; a `304` leaves the panel and cache untouched, a `200` replaces
both. A revalidation failure with a cache on screen keeps the panel rather
than entering `failure` — a stale panel is bounded, because every read and
write still re-derives permissions server-side. A **401** and a cached
document of an **unsupported schema version** both still surface
(`isUnauthenticated` / `needsAppUpdate`), cache or not. The screens gate
`isUnauthenticated` behind `status.isFailure`; `needsAppUpdate` is a
provider-level flag the host consumes — no screen reads it — and setting
it forces `status = failure`, so a stale panel can never mask a state the
user has to act on. `CachedSchema.document` is the decoded body,
re-encoded — never the parsed model, and never raw wire bytes, since
neither transport port ever exposes any. **The cache key is host-supplied,
and scoping it per signed-in user is the host's obligation, stated
prominently in the README**: `/schema` is per-user, so an unscoped key can
show a second user on the same device the first user's cached panel index;
a host that supplies no key gets no persistence, which fails safe. This is
P6b — the second of P6's six sub-projects. See the README's Schema caching
section for both ports' example implementations.

**Repeater.** A JSON-column `Repeater` field is editable from the phone.
`RepeaterComponent` parses `children` (the item template, published once),
`addable`, `deletable`, `minItems`, `maxItems`, `itemLabel`, `readOnly`; a
row's values live in the form state under the repeater's own name as a
`List<Map>` — `FormValues` treats the whole array as one leaf, never
flattening a row's field names into the top-level payload. `RepeaterFieldWidget`
renders one card per row from the template, an **Add** control when
`addable` and under `maxItems`, a **Remove** per row when `deletable` and
above `minItems` — both honour `state.enabled` and `readOnly`, same as
uploads: the server's word wins. Per-row client validation reuses the
existing validator against each row's own rules, so a required field left
blank in row 2 blocks submission with the error on row 2, not a generic
form error; a server `422` shaped `items.0.field` (Laravel's own per-item
key) lands in the same error map through `ResourceFormProvider`, which
checks only the first path segment against the writable repeaters on
screen. Editing a row clears only that row's stale errors — `change()`
compares each row's identity against the previous list, so a still-invalid
sibling row keeps its message. Three new `FilamentStrings`, all
English-default: `addItem`, `removeItem`, `repeaterReadOnly`. Known
weaknesses, stated in the README: no reordering (published as
`config.reorderable` for an interested host; this widget never offers it),
the item template is static (a `live()` field inside a row does not
re-settle), and a relationship repeater, a nested repeater and one whose
item template the server cannot round-trip all render read-only.
`RepeaterComponent.readOnly` defaults to `true` when `config.readOnly` is
absent — meant for a server predating repeater support, since a client must
never invent a capability the server did not declare — and the Laravel side
now publishes that key both ways round so the default is only ever reached
by such a server. `laravel_contract_test.dart` parses the committed
`contract/laravel-panel.json` and asserts an ordinary repeater arrives
editable and a refused one does not: the cross-package assertion that
was missing while both sides were internally consistent and jointly wrong,
rendering every ordinary repeater inert with both suites green. **No
break for a host implementing `ResourceDataSource` directly** — no new
abstract member was added to that interface; `RepeaterComponent` is a new,
additive `SchemaComponent` subtype, the same shape every prior phase's new
field type has taken. This is P6c — the third of P6's six sub-projects; the
Laravel server half (the `repeater` node, per-item rules, the
`RuleExtractor`/`WritableNames` name-space split) is `gait/filament-mobile`'s
own 0.3.0. See the README's Repeater section.

**Repeater close-out** (whole-branch review of P6c).

A row's children are now built through **the host's own `FieldRegistry`** —
the same one that built the repeater — instead of a fresh
`FieldRegistry.defaults()`. A host-registered custom field type, and a host
override of a built-in one, rendered everywhere on the form except inside a
repeater's rows: a silent inconsistency in a documented extension point.

`RepeaterFieldWidget`'s class docblock asserted that "the walker already
publishes a nested one `readOnly: true`". Nothing did — a nested repeater
shipped editable, and its server `422` arrives keyed `outer.0.inner.1.x`,
which this widget has no field to render against. The Laravel side now
publishes that flag (`gait/filament-mobile` 0.3.0), so the docblock, both
READMEs and the spec describe what actually ships. Nested rows still
round-trip; they are part of the outer array's value.

The server also refuses a repeater whose item template holds a child it
cannot round-trip (a `Hidden`, an unmapped type, a `disabled()` field) —
writing the array whole would delete that child's key from every row. Those
fields arrive `config.readOnly: true` and render inert with their stored
rows intact; `laravel_contract_test.dart` asserts the refusal arrives
through the committed `contract/laravel-panel.json`, the same cross-package
loop that caught the `readOnly` default.

`FieldState.errors` is still deliberately **not** forwarded into a row's
children: the only widget that reads the map is `RepeaterFieldWidget`
itself, for a nested repeater, and a nested repeater is now inert — its keys
are `outer.0.inner.1.x` while a nested widget would look them up as
`inner.1.x`. Every editable child shape gets its error through
`FieldState.error`, row-scoped, as before.

**A `422` no widget can render now reaches the banner instead of vanishing.**
A nested repeater is inert, but its rows still travel inside the editable
outer repeater's value, so the server can still refuse on
`outer_rows.0.inner_rows.0.x`. `ResourceFormProvider._applyServerErrors()`
mapped that key — its first segment names a repeater on screen — into the
field-error map, where nothing could look up a five-segment path and the
banner never saw it: Save did nothing and said nothing, the exact failure
that method exists to prevent. It now maps only the depth a widget can key
into, `<repeater>.<row>.<child>` — exactly three segments, since layout
nesting inside an item template does not lengthen Laravel's key and only a
nested repeater does — and anything deeper falls through to the banner
unattributed.

**Relations.** `ResourceSchema.relations` (`List<RelationDescriptor>`,
always present — `[]` when the server publishes none, and an *absent*
`relations` key reads identically: a server predating this release) is
what a resource's Filament relation managers become on mobile — **read
only**: no create, edit, delete, attach or detach, and the manager's own
filters, search and sorting are ignored. `RelationDescriptor` carries
`key`, `label`, `card` (the same `CardLayout` a resource's own list card
uses), and `recordKey` — the **related** model's own route key, not the
parent resource's.

`ResourceViewScreen` renders one `RelationSectionWidget` per published
relation automatically, no host wiring required for it to appear. Each
section fetches its own first page independently, through
`ResourceDataSource.relation(resourceKey, id, relation, {page})` — a new
abstract member on `ResourceDataSource`, **not** a port: `lib/ports/*`
gained nothing, and a host on `RestResourceDataSource` needs no change.
**A host implementing `ResourceDataSource` directly must add `relation()`
when upgrading** — the same obligation `cachedPanel()` and `uploadFile()`
already established in this release for that interface; it will not
compile until the member is there. A zero-row load renders an empty
state, never an absent section, and the reverse holds too — a relation the
server did not publish renders no section at all; a failed load renders
`relationFailed`, never a spinner left spinning.

"See all" appears only once a section's first page reports more rows than
it displayed, and calls `ResourceViewScreen`'s new optional `onSeeAllTap`
— **absent, not disabled, when the host never wires it**, the same rule
`onEditTap`/`onCreateTap` were fixed to follow in this same release (see
below). `RelationListScreen` + `RelationListProvider` are what a wired
`onSeeAllTap` typically opens: the full, paginated relation, mirroring
`ResourceListScreen`/`ResourceListProvider`'s shape but with no search
field and no sort button — `RelationDescriptor` carries neither block to
build them from. Three new `FilamentStrings`, all English-default:
`seeAll` (`'See all'`), `relationEmpty` (`'Nothing here yet'`),
`relationFailed` (`'Could not load'`).

**No-corpse affordance gates, applied everywhere they were missing.**
Three sites — the new "See all" button, and the pre-existing edit and
create affordances — shared the same wrong shape: render the button
whenever permitted, let an unwired callback silently no-op. All three now
gate on the callback being non-null too, so an unwired-but-permitted
control is absent rather than a dead tap target. Caught while building the
relation section, fixed at the root for all three rather than patched only
at the new call site.

**`ResourceListScreen`'s skeleton and list body are extracted into
`CardListSkeleton`/`PaginatedCardList`** (`ui/paginated_card_list.dart`,
newly exported), shared with `RelationListScreen` rather than copied. The
extraction is what surfaced and fixed a real bug: a first, unextracted cut
of `RelationListScreen` built its loading skeleton from the *relation's*
card layout, which does not exist on `ResourceRecord.fake()`'s fields,
rendering six blank cards during every relation load. `CardListSkeleton`
now takes no layout parameter at all — it always builds from
`ResourceSchema.fake().card` internally — which makes that class of bug
structurally impossible rather than merely fixed once.
`PaginatedCardList` also gained a `loadMoreFailed` retry affordance,
closing a latent gap in `ResourceListScreen` itself: a failed `loadMore()`
set an `errorMessage` nothing read, and the trailing row — keyed only on
`isLoadingMore`, which the catch had already cleared — simply **vanished**,
so the page that never arrived left no trace on screen and no way to
retry. (An earlier draft of this entry said the spinner spun forever; it
did not, and the silent version was the worse of the two.) Both screens
now share this widget, and both are covered by a test that reds when the
`loadMoreFailed:` wiring is cut.

Known weaknesses, stated in the README: a relation manager that narrows
its own query is invisible on mobile (the server refuses to publish it —
see the Laravel README's Relations section); the section loads once in
`initState` and does not refresh after a record action changes the
relation's membership; the manager's filters, search and sorting are
ignored; only the first two columns become a card, because the server
only derives that many; nothing is writable. This is P6d — the fourth of
P6's six sub-projects; the Laravel server half (the three authorization
gates, guard impersonation, and the refusal for a relation whose table
narrows its own query) is `gait/filament-mobile`'s own 0.3.0.

**Relations hardening** (P6d whole-branch review).

`RelationDescriptor` now **drops a relation whose `card` fills no slot**,
which is what its own docblock always claimed. An absent, null or `{}`
card parsed into an all-null `CardLayout` and was published — rendering a
heading over rows containing zero `Text` widgets, the disabled corpse this
package does not ship. Every other missing required field on a relation
node already dropped it; the card was the one that did not, and that is
the exact shape of the defect P6c's repeater paid for.

A **401 on page two** now reaches the unauthenticated state in both
`ResourceListProvider` and `RelationListProvider`. `loadMore()`'s catch set
`errorMessage`/`loadMoreFailed` but never `isUnauthenticated`, so a session
expiring mid-scroll showed a generic retry prompt forever — and every retry
401'd the same way. Keeping the rows is right for a timeout and wrong for a
signed-out user.

**`ResourceListScreen`'s pagination is now covered.** Mutating its scroll
threshold (`* 0.8` → `* 1.5`) and its `loadMoreFailed:` wiring (→ `false`)
left all 538 tests green, while the identical scroll mutation on the newer
`RelationListScreen` reds one — the older, more-used path had no pagination
test at all, and the retry affordance shipped without a test that it was
connected. Both screens now have both, and each new test was confirmed by
mutation to red.

**Rich text (read only).** An `EntryKind.rich` infolist entry renders as an
actual document instead of raw markup, through a new `RichDocument`/
`RichNode` parse of the server's `<path>.__rich` sibling and a new
`RichEntryTile` (exported) built entirely on `RichText`/`Column` — this
package's two runtime dependencies unchanged: `flutter`, `equatable`. **No
break for any host**: both are additive types, nothing existing was
renamed or removed, and a server predating this release simply never
publishes `rich_entry` or a `.__rich` sibling for this build to read. The
recognised vocabulary mirrors the server's closed set exactly — ten node
types (`doc`, `paragraph`, `text`, `heading`, `bulletList`, `orderedList`,
`listItem`, `blockquote`, `horizontalRule`, `image`) and six marks (`bold`,
`italic`, `link`, `strike`, `underline`, `code`) — and a node type outside
it renders its own descendant text as a paragraph rather than vanishing, so
a future server addition degrades gracefully instead of losing content. An
image with no `src` (a private-visibility attachment) is skipped rather
than rendered broken; an empty paragraph renders a blank line instead of
collapsing to zero height; overlapping decorations (`strike` + `underline`,
or `strike` on a link) combine instead of the last mark winning; rendering
uses `Text.rich` rather than a bare `RichText` specifically so it honours
`MediaQuery.textScalerOf(context)`, the same as every other tile in this
package. A card slot bound to the same rich column reads
`<path>.__rich.text` instead of the raw string — absent entirely when the
server had nothing to convert, and every consumer without it falls back to
today's raw value. **Links are host-wired**, exactly like
`onSeeAllTap`/`onEditTap`: `EntryRegistry.defaults(onLinkTap: ...)` passed
to `ResourceViewScreen.registry`. **Unwired, a link renders as plain,
unstyled text — not a blue underlined span that does nothing when
tapped** — the same absence-not-disabled rule this package has applied
everywhere else, now applied to styling rather than to a button: an
unwired host's readers cannot tell the text was ever a link. Both example
apps now wire `onLinkTap`. Known weaknesses, stated in the README: no
editing (the form field stays a plain textarea over the raw HTML string);
`attrs.textAlign` is published and ignored, pending the RTL/i18n slice; no
tables, no custom TipTap blocks. This is P6e — the fifth of P6's six
sub-projects; the Laravel server half (`rich_entry`, the `<path>.__rich`
sibling, Filament's own renderer, the sanitisation property) is
`gait/filament-mobile`'s own 0.3.0.

**RTL and i18n.** Every screen this package ships wraps its own returned
widget in a `Directionality` resolved from the panel's published
`direction`, **unconditionally, not a host opt-in** — the same "ships dead
unless nobody can leave it unwired" reasoning behind P6d's `fetchRelation`
and P6e's `onLinkTap`, applied here to a value that is correctness, not
preference. `PanelSchema.fromJson` propagates the panel's `direction` into
every `ResourceSchema` and `RelationDescriptor` at parse time, so no host
wiring is required anywhere: all six screens, plus every **route** this
package pushes — the sort sheet, the delete and action confirmation dialogs,
`showDatePicker`, `showTimePicker`, the remote-select search sheet and a
select field's dropdown menu — resolve direction from data the host already
passes, each pinned by its own test so deleting a single wrap reds a named
one. A `SnackBar` is not a route and needs no wrap: `ScaffoldMessenger`
renders it inside the `Scaffold`, already below the screen's own
`Directionality`. An absent `direction` (a server predating P6f) reads
as `ltr`, the same fallback the server itself normalises an unrecognised
value to. **Four** direction-unsafe widgets — two horizontal `left:`
paddings (one of them the rich-text blockquote's indent), an
`Alignment.centerRight`, and one composite padding — become
`EdgeInsetsDirectional`/`AlignmentDirectional`, and the blockquote's `left`
border moves with its indent (`BorderDirectional(start:)`), since a bar
painted on a fixed left edge lands under the text once the indent flips. **`textAlign` is finally honoured** on
`paragraph`/`heading` nodes, closing the gap P6e's rich text left open.
**Grouped digit runs are bidi-isolated under RTL**
(`isolateGroupedDigits`), so a phone number or a spaced IBAN keeps its own
group order inside Arabic text instead of the bidi algorithm reordering the
groups — measured with `TextPainter`, not assumed. The pattern is
deliberately tight (two or more digit groups separated by spaces or
hyphens, optional leading `+`) so it never touches a year, a price or a
plain count. A digit is ASCII, Arabic-Indic (U+0660–0669) or Extended
Arabic-Indic (U+06F0–06F9) — Dart's `\d` is ASCII-only, and the eastern
forms, the numerals an `ar` panel is most likely to contain, reverse with
the same measured signature. It runs downstream of `SemanticBadge`'s own colour lookup,
because the isolate characters are invisible but still characters — applied
upstream, a badge silently loses its colour under RTL only, since the
lookup key no longer matches the server's raw value. Known weaknesses,
stated in the README: the bidi rule is a heuristic, not a semantic parse — a
free-text value shaped like grouped digits is isolated whether or not it
is one; per-field content direction is not modelled, so an English panel
holding Arabic data still lays out left-to-right; text a host renders
itself is not covered; `FilamentStrings` remain host-supplied and
untranslated by design; translatable-field editing is untouched;
`RichEntryTile` isolates per mark leaf, so a digit run split across a bold
boundary is not isolated; the pattern has a leading `(?<!\w)` token
boundary but deliberately no trailing one, so a raw ISO timestamp still
isolates only its date half — harmless, and a trailing guard would split
the date itself; the idempotency guard on `isolateGroupedDigits`
is whole-string, not per-match. This is P6f — the sixth and last of P6's
six sub-projects, **closing P6**. The Laravel server half (`panel.locale`,
`panel.direction`, the `filament-panels::` namespace, `GET /dashboard`'s
own `direction`) is `gait/filament-mobile`'s own 0.3.0.

## 0.4.0 — 2026-08-06

**The client no longer invents a confirmation the panel never wrote.**

A successful action whose server response carries no message now shows no
snack bar. Filament sends a notification only when the action declared a
title — `CanNotify::sendSuccessNotification()` guards on
`filled($notification?->getTitle())` — so an action with no success title is
silent on the web panel, and an action that raises `Cancel` (which reaches
the client as a 200 with a null message) is silent there too. 0.2.0 showed a
generic "Done" for both, which claimed an outcome the panel had not stated.
The record re-fetch still happens, so the user's feedback is the record
changing on screen.

A **failed** action with no message still falls back to `actionFailed`, and
the asymmetry is Filament's own: it marks failure notifications
`->persistent()` and success ones not. A silent failure on the web still
leaves a page the user can read; on a phone a tap that produces nothing is
indistinguishable from a dead button.

**Breaking:** `FilamentStrings.actionDone` is removed — nothing renders it
any more. If you passed it, delete the argument; there is no replacement,
because the case it covered is now silence.

The wire is unchanged. No server release accompanies this.

## 0.3.0 — 2026-08-06

**Breaking.** The schema-level action types are gone: `ResourceAction`,
`ActionScope`, `ActionConfirmation`, and `ResourceSchema.actions`.

They came from the P0 design spec's §5.5 sketch — a resource-level `actions`
array with `row`/`bulk`/`header` scope and inline modal forms. The Laravel
package never emitted that key on `/schema`, and nothing in this package
ever rendered it, so `ResourceSchema.actions` was always `[]` in practice
and no host can be reading a value from it. Keeping them meant shipping two
vocabularies for one word, which had already cost a naming collision:
0.2.0's record-scoped confirmation had to be called
`RecordActionConfirmation` because `ActionConfirmation` was taken by the
dead type.

**If you referenced any of them, delete the reference** — there is no
replacement, because there was never a value. For actions that actually
work, use `ResourceRecord.actions` and `RecordAction` from 0.2.0: they
travel per-record on the record payload, because an action's visibility is
a fact about one record rather than a static fact about a resource.

The wire is unchanged. A server that sends a schema-level `actions` key
(none does) now has it ignored rather than parsed.

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
