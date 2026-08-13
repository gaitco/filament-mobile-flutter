![filament_mobile](https://raw.githubusercontent.com/gaitco/filament-mobile-flutter/main/art/banner.png)

# filament_mobile

Renders a Laravel Filament 5 panel as a native Flutter mobile admin, driven by
the JSON contract that `gait/filament-mobile` serves.

![How it works](https://raw.githubusercontent.com/gaitco/filament-mobile-flutter/main/art/diagram.png)

![Screens](https://raw.githubusercontent.com/gaitco/filament-mobile-flutter/main/art/showcase.png)

## Install

```bash
flutter pub add filament_mobile
```

Point it at a Laravel panel running [`gait/filament-mobile`](https://packagist.org/packages/gait/filament-mobile).

## Requirements

- **Flutter `>=3.44.0`** and Dart `^3.12.0`. A host on an older toolchain must
  upgrade before adding this package — `pubspec.lock`'s SDK constraint moves
  with it.
- Two runtime dependencies only: `flutter` and `equatable`.

## Quick start

Implement `FilamentTransport` over whatever HTTP client you already use, then
hand a `ResourceDataSource` to the screens. This is the example app's wiring,
trimmed to the shortest thing that runs — the example itself also passes a
schema cache, an upload transport, a file picker and a link handler:

```dart
final source = RestResourceDataSource(
  transport: MyTransport(baseUrl: 'https://panel.example.com', token: () => myToken),
);

// The panel index — every resource the signed-in user may see.
PanelIndexScreen(
  provider: PanelProvider(source),
  onResourceTap: (resource) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ResourceListScreen(
        provider: ResourceListProvider(source: source, resource: resource),
        onRecordTap: (record) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ResourceViewScreen(
              provider: ResourceViewProvider(
                source: source,
                resource: resource,
                id: record.id,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
```

**Navigation is yours.** Every screen takes an `onXTap` callback rather than
pushing routes itself, so the package never assumes your router. An affordance
whose callback you do not wire is **absent**, not disabled — this package does
not render controls that do nothing.

The default endpoint prefix is `/api/mobile-panel` — absolute, so it appends
correctly to a base URL with no trailing slash. A prefix that is a **whole
URL** (`https://api.example.com/mobile`) is passed through unchanged, for a
host whose HTTP client carries no base URL of its own.

A full runnable host — real HTTP transport, schema cache, upload, file picker
and link handling — is in [`example/`](example).

## What ships

| Feature | What you get |
|---|---|
| [Actions](#actions) | Buttons the server already authorised for this record |
| [Upload](#upload) | Single-file upload, through an additive port your existing transport need not implement |
| [Repeater](#repeater) | Add and remove rows, validated per row |
| [Radio](#radio) | Real radio buttons, parsed off `select`'s own model |
| [Tags](#tags) | Chips with a remove affordance, always a `List<String>` |
| [Key/value](#keyvalue) | Add/remove pairs, key and value cells gated independently |
| [Colour](#colour) | A text field with a live swatch, in the panel's own format |
| [Time and date bounds](#time-and-date-bounds) | `showTimePicker`, and the bounds a picker declares |
| [Relations](#relations) | A child list on the record screen — writable when the server names a child resource; "See all" opens the full paginated view |
| [Rich text](#rich-text) | A real document — headings, lists, quotes, emphasis, links |
| [Schema caching](#schema-caching) | Cold start renders from cache, revalidates behind it |
| [Dashboard](#dashboard) | Stat tiles render; charts drawn by the opt-in [`filament_mobile_charts`](https://pub.dev/packages/filament_mobile_charts) sibling, or your own builder |
| [RTL and i18n](#rtl-and-i18n) | The panel's direction, not the device's |

Everything below is reference. Each feature section ends with a **Known
weaknesses** list stating plainly what it does not do.

## Field types this client renders

Every wire type the server can publish for a **form** has a built-in widget:

`text` · `textarea` · `email` · `password` · `number` · `select` ·
`multiselect` · `radio` · `toggle` · `checkbox` · `date` · `datetime` ·
`time` · `color` · `file` · `tags` · `keyvalue` · `repeater`

Infolist entries render through `EntryRegistry`: `text_entry`,
`badge_entry`, `boolean_entry`, `image_entry` and `rich_entry`.

A card's **badge slot bound to a boolean column** renders a `BooleanBadge`
(`lib/ui/semantic_badge.dart`) — Filament's boolean-column idiom, a check or
a cross, instead of the literal word `true`. The colour goes through the
same semantic map a text badge uses: both key spellings are honoured
(`'true'/'false'`, then `'1'/'0'` — JSON object keys are strings, and `true`
as a PHP array key becomes `1`), falling back to `success`/`gray` when the
panel mapped neither. Detection happens on the record's **raw typed value**
before stringifying — after `toString()` a real bool and the string `"true"`
are indistinguishable, and the string must stay a text badge.

A type this build does not know renders as an `UnknownComponent` — a visible
placeholder in debug, skipped entirely in release, so a newer server never
breaks an older client. **Register your own** for a custom type, or to override
a built-in:

```dart
final registry = FieldRegistry.defaults()
  ..register('signature', (context, component, state) {
    return MySignaturePad(
      value: state.value as String?,
      onChanged: state.onChanged,
    );
  });

ResourceFormScreen(provider: provider, registry: registry);
```

That pairs with `config('filament-mobile.types')` on the server, which maps an
unmapped Filament component onto a type the contract already defines — see the
Laravel package's **Supported form inputs**.

## Implementing `FilamentTransport`

A host implements `FilamentTransport` over its own HTTP client, and optionally
a `PanelStateBuilder` to render loading, empty and failure states with its own
widgets. Two things about it are not guessable, and both bite at runtime rather
than at compile time.

### Reads throw, writes don't

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

### A 401 is not a broken server — `FilamentTransportException.statusCode`

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

## Actions

*Buttons the server decided this record may run.*

`ResourceRecord.actions` (`List<RecordAction>`, empty when the resource
opted none in) is the per-record list `GET /{resource}/{record}` publishes.
Absence means unavailable — there is no `enabled: false` to render greyed
out, so `ResourceViewScreen` renders exactly one button per entry, colored
through the same semantic vocabulary card badges use
(`SemanticBadge.colorFor()`, now public), and no disabled ones.

A `RecordAction` with a non-null `confirmation` is confirmed in the action's
own words — `heading`/`description`/`submit`/`cancel` — never the package's
generic delete-confirmation copy. An empty `submit` or `cancel` (the
server's fail-closed shape for a confirmation whose own copy closure threw)
is the client's cue to substitute its own string, not a signal to skip the
prompt: `confirmation` being non-null already decided that.

Run one through `ResourceDataSource.runAction(resourceKey, id, name)`, which
returns a sealed `ActionResult` — `ActionSuccess(message)` or
`ActionFailed(message)` — the same shape as `WriteResult` on the write path.
`ResourceViewProvider.runAction()` calls it, shows `message` through the
screen's existing snack-bar convention, and re-fetches the record on
success: an action's most common effect is changing exactly `permissions`
and `actions`, so the re-fetch refreshes both.

**A success with no message shows nothing**, and that is deliberate.
Filament only sends a notification when the action declared a title
(`CanNotify::sendSuccessNotification()` guards on `filled($title)`), so an
action without one is silent on the web panel — as is one that raises
`Cancel`, which arrives here as a 200 with a null message. Showing a generic
"done" would have the phone claim an outcome the panel never stated; the
user's feedback is the record itself changing after the re-fetch. A **failed**
action with no message does still fall back, because Filament marks failure
notifications `->persistent()` and success ones not: on a phone, a tap that
produces nothing at all cannot be told apart from a dead button.

Two more strings joined the `FilamentStrings` English-default rule above:
`actionFailed` (`'Could not run that action.'`) and `actionConfirm`
(`'Confirm'`). A host that upgrades and changes nothing still compiles and
still runs — and, per the same caveat as every other default, shows English
under server-translated action labels until the host supplies its own.

## Upload

*The host supplies the transport and the picker.*

A single-file `FileUpload` field is editable from the phone, through two
separate host-supplied pieces — same escape-hatch shape `chartBuilder`
already established for dashboard charts, and for the same reason: keeping
this package's two runtime dependencies (`flutter`, `equatable`) real for
every host, including the ones with no upload feature at all.

### Why upload is a second interface, not a fifth `FilamentTransport` method

`FilamentTransport` is an `abstract interface class`, and every host
implements it with `implements`. `implements` inherits the interface but
never an implementation, so adding a member to it — even one with a default
body — is a compile error (`non_abstract_class_inherits_abstract_member`) in
every existing host, verified against the analyzer rather than assumed.
Bytes don't fit in `post()`'s JSON body either: base64-encoding a 10 MB
photo produces roughly 13 MB of JSON held whole in memory on both ends, and
collides with PHP's `post_max_size`/`memory_limit` in ways that read as
server bugs, not client ones.

So upload is `FilamentUploadTransport`, a **separate, optional** port:

```dart
abstract interface class FilamentUploadTransport {
  Future<FilamentResponse> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    String field = 'file',
  });
}
```

A host that never uploads is untouched. A host that does implements both —
`class MyTransport implements FilamentTransport, FilamentUploadTransport`.
`RestResourceDataSource.uploadFile()` checks `transport is
FilamentUploadTransport` at call time; when it is not, the upload fails with
a message naming what to implement, never a throw the caller has to guard
against. Here is a full, real implementation over `package:http` — the
example app's, unedited:

```dart
@override
Future<FilamentResponse> upload(
  String path, {
  required List<int> bytes,
  required String filename,
  String field = 'file',
}) async {
  final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
    ..headers.addAll(_headers)
    ..fields['field'] = field
    ..files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

  final response = await http.Response.fromStream(
    await _client.send(request),
  );

  return FilamentResponse(
    statusCode: response.statusCode,
    body: response.body.isEmpty
        ? const {}
        : jsonDecode(response.body) as Map<String, dynamic>,
  );
}
```

Three statements. That brevity is the point: `package:http`'s
`MultipartRequest` already does the encoding work, so implementing this port
costs a host nothing beyond what it would write anyway to call the endpoint
directly.

### The host also supplies the file picker

Choosing a file needs a platform plugin this package will not force on a
host with no upload feature, so `ResourceFormScreen` takes an optional
`filePicker`:

```dart
typedef FilamentFilePicker = Future<PickedFile?> Function(SchemaComponent field);

class PickedFile {
  const PickedFile({required this.bytes, required this.filename});
  final List<int> bytes;
  final String filename;
}
```

An `image_picker`-backed one is a few lines:

```dart
ResourceFormScreen(
  // ...
  filePicker: (field) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    return PickedFile(
      bytes: await picked.readAsBytes(),
      filename: picked.name,
    );
  },
)
```

Returning `null` means the user cancelled; the field does nothing further,
same as any other cancelled picker. A picker that throws (a real plugin's
common failure — a denied permission) shows `FilamentStrings.uploadFailed`
rather than crashing the form.

**Without a `filePicker`, or without a transport implementing
`FilamentUploadTransport`, the field stays read-only** and shows
`FilamentStrings.filePickerUnavailable` — never a control that looks
tappable but cannot work, the same rule `chartUnavailable` follows for a
missing chart renderer. **`readOnly` from the server always wins over a
host-supplied picker**: a field the panel published `config.readOnly: true`
for (a multi-file field, or one whose constraints closure throws
server-side) shows `FilamentStrings.fileFieldReadOnly` and stays inert even
when the host wired up both pieces — the server's word is the gate, the
picker only fills in what the server already allowed.

### Upload happens on pick, not on save

Tapping choose runs the picker, then immediately calls
`ResourceDataSource.uploadFile()` — the control shows
`FilamentStrings.uploading` and disables itself for the duration, so a slow
upload cannot be double-fired by an impatient second tap. On success the
field's value becomes the returned path and the stored filename is shown; a
failed upload never clears whatever value the field already held.

`ResourceDataSource.uploadFile()` returns a sealed `UploadResult` — the same
shape as `ActionResult` — `UploadSuccess(path)` or `UploadFailed(message,
{statusCode})`, so a caller's `switch` is exhaustive.

A `422` (`statusCode == 422`) is this field's own refusal — too large, wrong
type — and lands on the field's error exactly like a write's per-field
validation error. Every other failure (a bare 403/500, an offline
transport, a host transport lacking the upload port) is not a fact about
what the user picked, so it reaches the form's error banner instead — the
same split `submit()` already makes between field-scoped and form-scoped
failures.

### Known weaknesses, carried from the server or inherent to the port

- **Orphaned files accumulate.** A user who picks a file and abandons the
  form leaves a stored file with no row pointing at it. This package does
  not claim or clean these up; a host that cares prunes the storage
  directory on its own schedule — see the Laravel README's Upload section.
- **No upload progress percentage.** `FilamentUploadTransport.upload()`
  returns a `Future`, not a stream, so the control can show "uploading…" but
  not "43%". A percentage would need a streaming port; revisit only if a
  real panel wants it.
- **The whole file sits in memory.** Both the picker's `PickedFile.bytes`
  and the multipart request body hold the file whole — a very large file on
  a low-memory device can fail before the server ever sees it. The field's
  own `maxSize`, enforced server-side, is the practical bound today.
- **Multi-file remains unusable.** A `FileUpload::multiple()` field
  publishes `config.readOnly: true` and shows `fileFieldReadOnly`
  permanently — this slice has nowhere on the server to save more than one
  path per column.

## Repeater

*Add and remove rows, validated per row.*

A JSON-column `Repeater::make('items')->schema([...])` field parses into
`RepeaterComponent` (`children` — the item template, published once, never
once per row — plus `addable`, `deletable`, `minItems`, `maxItems`,
`itemLabel`, `readOnly`) and renders through `RepeaterFieldWidget`: one
`Card` per row from the template, an **Add** control when `addable` and the
row count is under `maxItems`, and a **Remove** per row when `deletable` and
the row count is above `minItems`. A row's values live in the form state
under the repeater's own name as a genuine `List<Map>` — `FormValues` treats
the whole array as one leaf, the client-side mirror of the server's own
name-space split (see the Laravel README's Repeater section): the row
template's field names never flatten into the top-level form.

Both controls, and every field inside a row, honour `state.enabled` and
`readOnly` — the server's word wins, same as an upload field: a repeater the
panel published `config.readOnly: true` for shows the new `repeaterReadOnly`
string and stays inert even if the host's own gates would otherwise allow
editing. The server publishes that flag for two shapes (see below): a
nested repeater, and one whose item template holds a child the server
cannot round-trip. A relationship repeater is editable against a current
server — see the third known weakness below for what its save costs.

Each row's fields are built through **the host's own `FieldRegistry`** — the
same one that built the repeater — so a `FieldRegistry.register()` custom
type, or a host override of a built-in one, renders inside a row exactly as
it does everywhere else on the form.

**Per-row validation reuses the existing client validator against each row's
own rules**, so a required field left blank in row 2 blocks submission with
the error attached to row 2, not a generic whole-form error. A server `422`
does the same on the authoritative side: Laravel's own shape for a repeater's
per-item rule failure is `line_items.0.sku`, and `ResourceFormProvider`
matches that shape directly — first segment against the writable repeaters on
screen, and **exactly three segments**, which is the depth this widget can key
an error into. A deeper key belongs to a nested repeater
(`outer.0.inner.1.x`), which nothing on screen can render, so it goes to the
form's error banner unattributed rather than into a map no widget reads: a
refusal the user cannot see is a Save that does nothing and says nothing.
A row-scoped error at the renderable depth lands in the exact same map
`FieldState.errors` already reads for a client-side one. Editing a
row clears that row's stale errors specifically: a repeater's `onChanged`
always replaces the *whole* row list, so `change()` compares each row's
identity against the previous list and clears only the errors for rows that
actually changed — a still-invalid sibling row keeps its message.

Three new `FilamentStrings`, all English-default: `addItem` ('Add item'),
`removeItem` ('Remove'), and `repeaterReadOnly` ('These items cannot be
changed.') — same rule as every other string in this package: a host that
upgrades and changes nothing still compiles, still runs, and shows English
under otherwise-translated labels until it supplies its own.

### Known weaknesses, stated now

- **No reordering.** The server may publish `config.reorderable: true` for a
  host rendering its own repeater; `RepeaterFieldWidget` never offers it
  regardless of what is published.
- **The item template is static.** A `live()` field inside a row does not
  re-settle that row — `/state` settles a flat form, and a row coordinate is
  a problem this slice does not solve.
- **A relationship repeater's save is delete-all-then-recreate.** Against a
  current server the field is editable and writes through Filament's own
  `saveRelationships()` — but its state on the wire is keyless, so every
  save deletes the existing child rows and re-creates them from the
  submitted state (pinned server-side in `RepeaterWriteTest`). Nothing this
  widget can soften; worth knowing before editing rows other tables point
  at by id.
- **An untouched legacy value in a stored row can now block submission.**
  Per-row validation seeds a synthetic `FormValues` per row, and a row
  cannot reconstruct the stored-vs-touched distinction the top-level form
  uses to spare a legacy value the user never edited — so every validated
  child in a row is treated as dirty. That is over-eager on purpose (a
  malformed colour the user *just typed* into a row previously submitted
  unchallenged), but the trade-off cuts the other way too: a stored row
  carrying a legacy colour value fails the format check even if the user
  never opened that row.
- **A nested repeater renders read-only.** A repeater inside another
  repeater's item template is published `config.readOnly: true` by the
  server, and this widget honours that flag like any other — the nesting
  needs no special case here. Its rows still round-trip (they are part of
  the outer array); they simply cannot be edited from a phone, because a
  nested row's `422` comes back keyed `outer.0.inner.1.x` and this widget
  has no field to render it against — that message reaches the form's error
  banner instead, so a save the server refuses always says something. Two
  levels of row coordinate is a different problem, and
  `filament-mobile:doctor` reports the shape server-side.
- **A repeater with a child the server cannot round-trip is read-only.** A
  `Hidden`, an unmapped component, a `disabled()` field, or a relation-write
  child forced back into the row with `->dehydrated(true)` in the item
  template means the whole array write would delete that child's key from
  every row, so the server refuses the field outright rather than offering a
  control that eats data. Its stored rows are still returned on `GET` and
  still render, inert. `doctor` names the offending child.
- **A `select` with `optionsUrl` inside a row fetches through
  `FieldState.searchOptionsFor`.** The per-field variant of
  `FieldState.searchOptions`, public for exactly this caller: a row's select
  is rendered off the item *template*, so its lookup must be bound to the
  child's own name — handing the repeater's `searchOptions` closure down
  would query the repeater's field, not the child's. Leaf fields keep
  reading `searchOptions`, and the server side descends through the repeater
  to find the child (see the Laravel README's Repeater section). Against a
  server predating that descent the control degrades to an empty dropdown.

**Why `readOnly` defaults to `true` when the key is absent:** an absent
`config.readOnly` means a server predating repeater support, and this client
never invents a capability the server did not declare — so it renders inert
rather than guessing it can accept edits. A server on this contract states
the key **both ways round** (`false` for an ordinary JSON-column repeater,
`true` for a refused one), so the default is only ever reached by an older
server. It is asserted end-to-end, not assumed: `laravel_contract_test.dart`
parses the committed `contract/laravel-panel.json` — real Laravel output —
and asserts an ordinary repeater arrives editable while a relationship one
and one with a non-round-tripping child do not. That test exists because the first cut of P6c had the server
publishing the key for the refused case only, which rendered every ordinary
repeater inert with both packages' own suites green.

## Radio

*Real radio buttons, parsed off `select`'s own model.*

A `radio` node parses into `SelectComponent` — the same model type a
`select`/`multiselect` node parses into, `radio` joining the `switch (type)`
in `SchemaComponent.fromJson` (`schema_component.dart`), alongside `select`
and `multiselect` — but renders through a distinct, new
`RadioFieldWidget`, never `SelectFieldWidget`. One stacked
`RadioListTile` per option, single selection, `state.enabled` and the
server's `readOnly` both honoured — no dropdown, no search field, because a
`radio` node never carries `config.optionsUrl` (see the Laravel README's
Radio section for why an over-cap radio inlines every option instead).

### Known weaknesses, stated now

- **`Radio::isInline()` is not on the wire.** Options always stack one per
  row, the treatment `RadioFieldWidget` uses unconditionally.

## Tags

*Chips with a remove affordance; the value is always a `List<String>`.*

A `tags` node parses into `TagsComponent` (`separator`, `suggestions`) and
renders through `TagsFieldWidget`: existing tags as chips with a remove
affordance, a text field that commits a new tag on submit, and
`suggestions` offered when the field published any. `separator` is read for
display only — a client never builds or parses the delimited form; the
value in form state is always a `List<String>`, exactly as the server
publishes and expects it, separator-configured or not.

One documented exception, on the server's side: a **relation row** whose
child model is served by zero or by several opted-in resources has no
resolvable owner, so the server cannot know the separator and publishes the
stored delimited `String` rather than guessing a split (see
`contract/README.md`'s Tags section). `_TagsFieldWidgetState._tags` already
tolerates it — a non-`List` reads as no tags rather than throwing — so the
row renders empty chips instead of crashing. Stated here because "always a
`List<String>`" is otherwise the claim a host would trust.

The new `FilamentStrings.tagHint` (`'Add a tag'`) labels the input, English
default as always — a host that upgrades and changes nothing still
compiles and still runs.

### Known weaknesses, stated now

- **`splitKeys`, `tagPrefix` and `tagSuffix` are not on the wire.** A tag
  commits on submit only; this widget has no prefix/suffix presentation to
  reproduce.

## Key/value

*Add and remove pairs; a row's key or value cell renders as text, not a
disabled input, when its gate is off.*

A `keyvalue` node parses into `KeyValueComponent` (`addable`, `deletable`,
`editableKeys`, `editableValues`, `keyLabel`, `valueLabel`,
`keyPlaceholder`, `valuePlaceholder` — all four booleans default to `true`
when absent, matching the server's own default) and renders through
`KeyValueFieldWidget`: one row per pair, an **Add** control when `addable`,
a **Remove** per row when `deletable`. Two pre-existing strings from the
Repeater section above are reused rather than duplicated:
`FilamentStrings.addItem` and `.removeItem`.

**A gate that is off makes its control absent, not disabled.** A row whose
key is not editable renders its key as plain, unfocusable `Text`, never a
greyed-out text field — same rule this package applies to every other
affordance a server gate turns off. `editableValues` governs the value cell
the identical way, independently: one gate off and the other on renders a
row with an editable value beside a read-only key, which is a legitimate
combination the server can configure and this widget must render correctly.

**Rows carry identity independent of their key**, which the first cut of
this widget got wrong. `_pairs` is held as `List<MapEntry<String, String>>`
state, seeded once and mutated in place rather than re-derived from the
map on every build — so renaming a key that transiently collides with
another row's key no longer merges the two rows into one, and adding two
rows in a row produces two rows, not one.

### Known weaknesses, stated now

- **No reordering**, matching the repeater — this widget has never offered
  one for either array-valued field.
- **All four gates are client hints.** See the Laravel README's Key/value
  section for what "not enforced by the write path" means in practice, and
  for the contrast with `disabled`, which this package's write path *does*
  enforce.

## Colour

A `color` field renders as a **text field with a live swatch** — not a colour
wheel. This package takes no colour dependency, and a hand-rolled picker's
colour maths is easy to get subtly wrong and hard to test, so the honest
treatment won.

The swatch updates as you type and **holds the last valid colour** when the
text is malformed, rather than blanking.

**The value is never converted.** A field the panel declared as `rgb` emits
`rgb`; the widget parses all four formats (`hex`, `hsl`, `rgb`, `rgba`) and
returns the one it was given, byte for byte where you did not edit it.

A malformed value blocks submission — **but only once you have edited that
field**. The check is gated on `FormValues.dirty` for two reasons: the client
must not invent a constraint the server does not have, and it must not block a
save over a value that was already in the database when the form opened. One
new `FilamentStrings` entry carries the message, English default as always.

### Known weaknesses, stated now

- **No graphical picking**, deliberately.
- **No format conversion**, deliberately.
- **The `hsl` pattern rejects a fractional hue** while accepting fractional
  saturation and lightness — faithful to Filament's own regex, not a decision
  made here.
- **A malformed colour inside a repeater row is not blocked**, because repeater
  rows synthesise a fresh `dirty` set. Pre-existing behaviour of the row
  validator rather than something this field introduced.

## Time and date bounds

`DateKind` is now a three-way — `date`, `datetime`, `time` — and a `time` field
goes straight to Flutter's own `showTimePicker`, so it costs no dependency.

**Bounds now arrive.** `DateComponent.minDate` / `.maxDate` have been parsed
since this package was written and were always null, because the server never
published them. They are live as of the matching Laravel release, and the
picker clamps to them.

`DateComponent.unreadableBounds` names any bound that **arrived and would not
parse**, which is different from one that was never declared: the first is a
contract violation and warns in debug builds, the second is ordinary. The value
still degrades to `null` either way — a picker with a wrong limit is a
nuisance, a crashed form is an outage.

Two bound shapes parse, because the server publishes what the panel declared
rather than normalising it: a bare `"09:00"` and a full
`"2026-01-01 09:00:00"`.

### Known weaknesses, stated now

- **Bounds are hints.** The server refuses an out-of-range value only if the
  panel declared a rule saying so.
- **A `seconds` field resets seconds when the time changes.** They are
  preserved when the hour and minute are untouched; a genuinely new time starts
  at `:00`, because welding a stale `:30` onto a newly picked 16:20 would be a
  time nobody chose.
- **Step sizes and disabled dates are not published**, so the phone may offer a
  value the web panel's own controls would not.

## Relations

*A labelled section on the record screen; "See all" opens the full list.*

`ResourceSchema.relations` (`List<RelationDescriptor>`, **always present** —
`[]` when the server publishes none, and read the same way on an *absent*
`relations` key: a server predating this feature) is what a resource's
Filament relation managers become on mobile. No filters, search or
sorting — see the Laravel README's Relations section for the full server
picture, including why a relation manager that narrows its own query is not
published at all. Against a current server a relation can also be
**writable**, which is what its descriptor's `resource` key announces.

Each `RelationDescriptor` carries `key`, `label`, `card` (the same
`CardLayout` a resource's own list card uses), `recordKey` — the
**related** model's own route key, not the parent resource's, and not
always `id` — and `resource`, the child **resource's** key.
`RestResourceDataSource.relation()` parses each row by
`relation.recordKey`, never the parent's. **`resource` is the write
capability flag**: the server publishes it only when exactly one registered
resource owns the related model, and the parser reads an absent, null or
wrong-typed value as *absent* — read-only, never a throw, the same
absence-means-unavailable rule `readOnly` already follows.

### The section, and where it fetches from

`ResourceViewScreen` renders one `RelationSectionWidget` per entry in
`resource.relations` automatically — nothing a host has to wire for a
published relation to appear. Each section fetches its own first page
independently of the record's own load, through
`ResourceDataSource.relation(resourceKey, id, relation, {page})`:

```dart
abstract interface class ResourceDataSource {
  // ...
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
  });
}
```

**This is a member on `ResourceDataSource`, not a port, and no port gained
one.** `lib/ports/*` (`FilamentTransport` and friends) are what a host
implements directly over its own HTTP client; `ResourceDataSource` lives in
`lib/data/`, is implemented in production only by
`RestResourceDataSource`, and gains a member almost every release — a host
on `RestResourceDataSource` needs no change at all. Fetching goes through
the data source, not a host-supplied closure — an earlier cut of this
feature took a raw `Future<Map<String, dynamic>> Function()` from the host
and was corrected before release: a screen given no closure rendered
nothing for a published relation, which is exactly the class of bug this
package's own read path exists to prevent.

One section's slow or failing endpoint never blocks or blanks its
siblings — each owns its own request and its own loading/empty/failure
state, the same isolation `ResourceViewScreen`'s own record load already
has from its relation sections.

**A relation that loaded successfully with zero rows renders an empty
state, never an absent section — and the reverse holds too: a relation the
server did not publish renders no section at all.** Empty and absent are
different statements, and this widget is what keeps them looking different
on screen; a failed load renders `FilamentStrings.relationFailed`,
never a spinner left spinning — the exact incident recorded in
`docs/superpowers/HANDOFF.md` that this package's standing pilot lesson is
aimed at.

### "See all" — host-owned navigation, absent when unwired

A section shows a "See all" affordance only once its first page reports
more rows than it displayed. Tapping it calls `ResourceViewScreen`'s
optional `onSeeAllTap`:

```dart
ResourceViewScreen(
  provider: viewProvider,
  onSeeAllTap: (relation, recordId) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => RelationListScreen(
        provider: RelationListProvider(
          source: dataSource,
          resourceKey: resource.key,
          id: recordId,
          relation: relation,
        ),
      ),
    ),
  ),
)
```

**A host that never wires `onSeeAllTap` gets no button at all** — the same
absence-not-disabled rule `onEditTap`/`onCreateTap` already follow in this
package: a control the host cannot actually drive must not render enabled
and silently no-op on tap. Where to push, and with what navigator, is
entirely the host's call; this package has no router opinion.

### The full list — `RelationListScreen` / `RelationListProvider`

`RelationListProvider` mirrors `ResourceListProvider`'s shape (`status`,
`records`, `errorMessage`, `isUnauthenticated`, `hasMore`, `isLoadingMore`,
scroll-triggered `loadMore()`) but fetches through
`ResourceDataSource.relation()` instead of `.list()`, and owns its own
`ResourceDataSource` directly rather than taking a host-wired closure — the
same seam the section widget uses. `RelationListScreen` mirrors
`ResourceListScreen`'s skeleton, scroll pagination and `PanelViewState`
mapping, reusing the same `CardListSkeleton`/`PaginatedCardList` widgets
both screens share — but carries **no search field and no sort button**:
`RelationDescriptor` has neither a `search` nor a `sorts` block to build
them from, because a relation manager's own filters, search and sort are
not part of this slice's contract at all. The screen's title is the
relation's own `label`.

Three new `FilamentStrings`, all English-default, same rule as every other
string in this package: `seeAll` (`'See all'`), `relationEmpty`
(`'Nothing here yet'`), `relationFailed` (`'Could not load'`).

### Writes — the child resource's form, the relation's endpoint

A relation whose descriptor carries a `resource` key is writable end to end.
Three members join `ResourceDataSource`, beside `relation()`:

```dart
Future<WriteResult> createRelation(String resourceKey, Object id, RelationDescriptor relation, Map<String, dynamic> values);
Future<WriteResult> updateRelation(String resourceKey, Object id, RelationDescriptor relation, Object childId, Map<String, dynamic> values);
Future<WriteResult> deleteRelation(String resourceKey, Object id, RelationDescriptor relation, Object childId);
```

**This is a breaking change for a host with its own `ResourceDataSource`
implementation** — the interface gained three methods, so it will not
compile until it adds them. A host on `RestResourceDataSource` needs no
change at all; the REST implementations ship there, keyed off
`relation.recordKey` exactly as the read is. The same "member, not port"
reasoning as `relation()` itself applies: `lib/ports/*` stays untouched.

The form a row is edited in is the **child resource's own**
`ResourceFormScreen` — only the write target changes. That override is one
small value, `RelationSubmitTarget` (parent resource key, parent record id,
the relation), handed to `ResourceFormProvider.submitTarget`: null — every
form outside a relation — submits to the resource's own endpoints exactly as
before; non-null redirects *only* the write, so validation, the `422`
mapping and the error banner are shared verbatim (the server keys a relation
write's `422` by the same child-form field names this screen renders).
Create vs update is decided by the provider's own `recordId`, exactly as
the resource write path already decides it.

`RelationListScreen` takes an optional `childResource` (the resolved
`ResourceSchema` for `descriptor.resource` — resolving it is the host's one
job; `ResourceDataSource` already fetches schemas). Every affordance is
**permission-gated off the child resource's published `permissions`**: an
Add button on `create`, per-row edit and delete on `update`/`delete`, and a
null `childResource` or a false flag renders **no control at all** — the
standing absence-not-disabled rule. Delete confirms through the same dialog
`ResourceViewScreen`'s own delete uses, one level down, reusing the existing
`deleteConfirmTitle`/`deleteConfirmBody`/`deleteConfirm`/`cancel` strings.
The per-row controls arrive through two new, generally-useful slots —
`ResourceCard.trailing` and `PaginatedCardList.rowTrailing` — rather than a
relation-specific card fork.

**The section refreshes when the record does.** `RelationSectionWidget`
takes an optional `parent` (the `ResourceViewProvider` it sits under) and
reloads when the parent finishes a reload — a record action that changed
relation membership no longer leaves stale rows until the user leaves and
returns. It listens only for a **success** notification: a failed parent
reload leaves the section showing what it already had, which is strictly
better than blanking good rows behind the parent's error.

### Known weaknesses, stated now

- **A relation manager that narrows its own query is invisible on
  mobile.** The server refuses to publish it at all — see the Laravel
  README's Relations section for why — so there is nothing here for this
  client to render around it.
- **The section refreshes only through `parent`.** Wire
  `RelationSectionWidget.parent` (the record screen's own provider) and a
  completed parent reload refreshes the section; without it the section
  loads once, in `initState`, and shows stale rows after an action that
  changes the relation's membership until the user leaves the screen and
  returns.
- **The relation manager's filters, search and sorting are ignored.** The
  list arrives in relation order, unfiltered — matching the server exactly,
  which itself does not evaluate them.
- **Only the first two columns become a card**, because the server only
  derives that many. A relation whose meaning lives in its third column
  looks empty of information on the phone too.
- **Writes need the server to name a child resource.** A relation whose
  descriptor has no `resource` key — zero or several registered resources
  own the child model, or the server predates relation writes — is a read
  path here exactly as before. Attach and detach are not exposed on either
  side.

## Rich text

*The document renders; links are host-wired, and absent when unwired.*

An infolist entry with `EntryKind.rich` (a `->prose()` `TextEntry`, or a
model column registered with `HasRichContent`) renders as an actual
document via `RichEntryTile`, this package's own export — headings,
bulleted and numbered lists, blockquotes, horizontal rules, images, and
bold/italic/strike/underline/code, using `RichText`/`Column`, this
package's two runtime dependencies unchanged. A card slot bound to the same
column shows its flattened plain text, never the raw markup: the record's
`<path>.__rich` sibling (`{"doc": …, "text": …}`) is absent entirely when
the server had nothing to convert, and every consumer without it falls
back to today's raw string.

`RichDocument.fromJson` parses the `<path>.__rich` sibling into a
`RichDocument` — a `RichNode` tree rooted at `doc`. The vocabulary this
build recognises mirrors the server's own closed set exactly:

```
NODES: doc, paragraph, text, heading, bulletList, orderedList,
       listItem, blockquote, horizontalRule, image
MARKS: bold, italic, link, strike, underline, code
```

**An unrecognised node renders its descendant text as a paragraph, never
nothing.** A future Filament release adding an eleventh node type must not
make a paragraph vanish — silent content loss is worse than plain-looking
text, so `RichNode.fromJson` carries an unknown `type` through rather than
rejecting it, and `RichEntryTile` falls back to `_descendantText` for
anything its `switch` has no case for. **An image with no `src`** — the
server nulls it for a private-visibility attachment — is skipped rather
than rendered broken. **An empty paragraph** (a ProseMirror blank-line
separator) renders a single space rather than collapsing to zero height, so
blank lines in the source document stay visible as blank lines. **Marks
combine**: `strike` and `underline` on the same run — or `strike` on a link,
which already carries `underline` — both survive, because decorations
accumulate and are merged once via `TextDecoration.combine` rather than each
mark overwriting the last. Rendering uses `Text.rich`, not a bare
`RichText`, specifically so it honours `MediaQuery.textScalerOf(context)`
like every other tile in this package — a bare `RichText` ignores the
user's system font-size setting.

### Links need a launcher this package will not take

Opening a URL is a platform concern (`url_launcher` or similar), and this
package ships **exactly two** runtime dependencies — `flutter` and
`equatable` — so it takes no opinion on how a host opens one. Tapping a link
is host-wired exactly like `onSeeAllTap`: the host passes its own
`EntryRegistry.defaults(onLinkTap: ...)` to `ResourceViewScreen.registry`.

```dart
ResourceViewScreen(
  provider: viewProvider,
  registry: EntryRegistry.defaults(
    onLinkTap: (href) => launchUrl(Uri.parse(href)), // the host's own package
  ),
)
```

**A host that never wires `onLinkTap` gets a link rendered as plain,
unstyled text — not a blue underlined span that does nothing when tapped.**
This is the same absence-not-disabled rule `onSeeAllTap`/`onEditTap` already
follow, applied to styling rather than to a button: a reader cannot tell an
unwired link was ever a link, which is the honest state, since this package
cannot make good on tapping it. `EntryRegistry` is the override point rather
than a new callback on `ResourceViewScreen` — a host that also wants a
custom entry type (see `EntryRegistry.register`) wires both through the one
registry it already owns.

### Known weaknesses, stated now

- **No editing.** The form field for a rich column stays a plain textarea
  over the raw HTML string — a user reads formatted text and edits markup.
  A real editor is a much larger build this slice does not attempt.
- **`attrs.textAlign` is published and ignored.** It belongs to the RTL/i18n
  slice.
- **No tables, no custom TipTap blocks.** Outside the closed vocabulary; an
  unrecognised node type renders its descendant text as a paragraph rather
  than disappearing, so content survives even where formatting does not.

## Schema caching

*Cold start renders instantly, then revalidates behind it.*

`/schema` is a ~200 KB document, and until now `PanelProvider.load()` showed
a spinner for every fetch of it, every launch. Two separate, optional ports
close that gap — separate for the same reason `FilamentUploadTransport` is:
`FilamentTransport` is an `abstract interface class`, hosts implement it with
`implements`, and `implements` inherits no implementation, so adding a member
to it is a compile error in every existing host.

**Without either port, behaviour is exactly what it is today** — in-memory
only, a full document fetched every time, no spinner change, no regression.
This is not a degraded mode; it is the honest no-op.

```dart
abstract interface class FilamentConditionalTransport {
  /// GETs [path], sending `If-None-Match: <etag>` when [etag] is non-null.
  /// A 304 must come back with `notModified: true` — never a throw, and
  /// never a synthesised empty body.
  Future<ConditionalResponse> getConditional(String path, {String? etag});
}

abstract interface class FilamentSchemaCache {
  Future<CachedSchema?> read(String key);
  Future<void> write(String key, CachedSchema value);
  Future<void> clear(String key);
}
```

A host that implements neither is untouched. A host that implements
`FilamentConditionalTransport` alone gets revalidation with no persistence —
pointless on its own, since there is nothing cached to revalidate against,
but harmless. The two ports earn their keep together: `FilamentSchemaCache`
persists the document, `FilamentConditionalTransport` lets a cold start ask
the server "is my cached copy still good?" for the price of an empty 304
instead of the whole document.

Here is the example app's `FilamentConditionalTransport`, unedited — the
same brevity argument as upload's three statements, this time because
`package:http`'s own `Response` already carries everything needed:

```dart
@override
Future<ConditionalResponse> getConditional(String path, {String? etag}) async {
  // Deliberately not routed through get(): get() throws on every non-2xx,
  // and a 304 is one — it would arrive there as an indistinguishable
  // thrown failure instead of the "unchanged" outcome the caller needs.
  final response = await _client.get(
    Uri.parse('$baseUrl$path'),
    headers: {..._headers, if (etag != null) 'If-None-Match': etag},
  );

  if (response.statusCode == 304) {
    return ConditionalResponse(
      notModified: true,
      etag: response.headers['etag'],
    );
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw FilamentTransportException(
      _messageOf(response),
      statusCode: response.statusCode,
    );
  }

  return ConditionalResponse(
    notModified: false,
    body: jsonDecode(response.body) as Map<String, dynamic>,
    etag: response.headers['etag'],
  );
}
```

And a `FilamentSchemaCache`, in-memory for the example — a real host reaches
for `shared_preferences` or Hive, whatever it already carries; this package
adds neither as a dependency:

```dart
class InMemorySchemaCache implements FilamentSchemaCache {
  final _entries = <String, CachedSchema>{};

  @override
  Future<CachedSchema?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, CachedSchema value) async {
    _entries[key] = value;
  }

  @override
  Future<void> clear(String key) async {
    _entries.remove(key);
  }
}
```

`CachedSchema.document` is the decoded body, re-encoded — **never the raw
JSON string, and never the parsed model.** Neither transport port ever
exposes raw wire bytes; both `get()` and `getConditional()` hand back an
already-decoded `Map<String, dynamic>`, so there is no original JSON string
in this package to store. Storing `jsonEncode()` of that same decoded map,
rather than the parsed `PanelSchema`, is what lets a key this package's
parser does not yet recognise survive the round trip instead of being
silently dropped on write.

### The cache key is the host's, and scoping it is a safety property

**`FilamentSchemaCache`'s key is supplied by the host, and the package never
invents one.** `/schema` is per-user — policies filter which resources
appear — so a cached document is one user's view of the panel index. **A
cache key that is not scoped per signed-in user — a constant, or one that
does not change across a sign-out/sign-in — lets a second user on the same
device open the first user's cached panel index**, before a single request
reaches the server. This package cannot enforce the right key: it has no
identity concept, by design, the same reasoning that keeps login and token
storage out of scope entirely. Scope the key to something that changes with
the signed-in user — a user id, a hash of the session token — and clear the
cache on sign-out if the host does not already rotate the key.

**A host that supplies no key gets no persistence**, which fails safe: the
same honest no-op as omitting the port entirely, never a cache that silently
serves the wrong user's data. An empty or whitespace-only key counts as no
key — `cacheKey: user?.id ?? ''` must never become a shared, unscoped
persistent key when nobody is signed in.

### Cold start: render cached, revalidate behind it

`PanelProvider.load()` reads the cache first. When there is a usable entry
it publishes the cached panel immediately — `status` goes straight to
`success`, never `loading` — and only then revalidates over the network. A
304 changes nothing; a 200 replaces the panel and rewrites the cache.
`status = loading` is therefore structurally unreachable once a cache is
published: no spinner ever flashes over content the user is already looking
at.

This cache-then-revalidate pass runs on a cold start — a fresh
`RestResourceDataSource`. Within one data source's lifetime the panel is
memoized after the first successful load, so a later `load()` on the same
instance re-publishes that panel without another network revalidation; a
new data source (a new app launch) starts the cycle again.

**A revalidation failure with a cache already on screen is not a failure
state.** The panel stays exactly as it was, and the user is never shown an
error for a background request they never made — a stale panel is bounded:
`/schema` describes structure, and every read and write still hits the
server, which re-derives permissions on every request. A cached panel cannot
grant access the server will not. A *cold* failure with no cache behaves
exactly as it does without either port: `PanelFailure`.

**Two outcomes still surface even with a cache on screen**, because both
name a state the user has to act on, not a fact about staleness:

- A **401** during revalidation still sets `isUnauthenticated` and
  `status = failure` — a signed-out session must not keep showing a panel,
  cached or not.
- A cached document of a **newer, unsupported schema version** is discarded
  and refetched, never rendered — `PanelSchema.fromJson` already throws
  `UnsupportedSchemaVersionException` for one, and stale bytes must never be
  the reason `needsAppUpdate` fails to surface.

The screens gate `isUnauthenticated` behind `status.isFailure`.
`needsAppUpdate` is a provider-level flag the host consumes — no screen
reads it — and setting it forces `status = failure`, so neither state can
be masked by a stale panel sitting in `success`.

### Known weaknesses, stated now

- **A 304 does not save server CPU** — see the Laravel README's Schema
  caching section; the document is still built to hash it.
- **The panel can be one revalidation stale.** Bounded by the reasoning
  above: structure only, and the server re-derives every permission on
  every request regardless of what `/schema` last said.
- **Cache correctness depends entirely on the host's key.** A host that keys
  the cache badly — a constant, say — can show one user another's panel
  index. The package cannot detect this; it is documented as the host's
  obligation, in the same class as "the host owns auth."
- **No eviction.** One document per key, overwritten in place; a host that
  creates unbounded keys grows unbounded storage.

## Dashboard

*Stats render; charts come from the opt-in sibling package, or your own builder.*

`DashboardProvider` + `DashboardScreen` follow the same provider/screen
shape as every other read screen: `LoadStatus`, skeleton-first loading,
pull-to-refresh, `PanelUnauthenticated` on a 401. `DashboardProvider.load()`
calls `ResourceDataSource.dashboard()`, which parses `GET /dashboard` into a
`DashboardData` — a list of `DashboardWidgetData`, sealed into
`StatsWidgetData` (a row of `StatData` cards) and `ChartWidgetData` (a
labelled axis and one or more `ChartDataset`s), so a `switch` over a widget
is exhaustive. Values are live on every read — the panel has no static
dashboard document to cache — so pull-to-refresh genuinely re-runs the
panel's queries, not a cached replay. A successful load of zero widgets
renders `PanelEmpty` with the new `dashboardEmpty` string, not a blank
screen.

**Stat cards render fully, including the sparkline.** `StatData.chart` (a
`List<double>?`) draws through `StatSparkline`, a hand-rolled
`CustomPainter` — a polyline with no axes, labels or touch handling. Its
colour comes from `SemanticBadge.colorFor()`, the same semantic vocabulary
(`success`, `danger`, …) action buttons already use; there is no second
palette to configure.

**Charts are published, not drawn — read this before assuming the package
can't do charts.** `ChartWidgetData` carries parsed `labels` and
`ChartDataset`s, but this package draws none of it itself. That is not a
missing feature; it is what keeps the two-dependency promise from the
Requirements section above (`flutter` + `equatable`, nothing else) true for
every host, including the ones with no dashboard. `DashboardScreen` takes
an optional `chartBuilder`:

```dart
typedef DashboardChartBuilder =
    Widget Function(BuildContext context, ChartWidgetData data);
```

A host that wants charts renders them with whatever charting package it
already has. The companion package
[`filament_mobile_charts`](https://pub.dev/packages/filament_mobile_charts)
is the ready-made answer — one dependency, one line, every chart type the
server can publish drawn with `fl_chart`:

```dart
DashboardScreen(
  provider: dashboardProvider,
  chartBuilder: flChartBuilder(),
)
```

Or hand-roll the builder against your own charting package, in about ten
lines:

```dart
DashboardScreen(
  provider: dashboardProvider,
  chartBuilder: (context, data) => LineChart(
    LineChartData(
      lineBarsData: [
        for (final series in data.datasets)
          LineChartBarData(spots: [
            for (var i = 0; i < series.data.length; i++)
              FlSpot(i.toDouble(), series.data[i]),
          ]),
      ],
    ),
  ),
)
```

**Without a `chartBuilder`, a chart card renders its heading and the new
`chartUnavailable` string** ("No chart renderer supplied.") — never a blank
box. This is the same honest-empty-state rule every other screen in this
package follows: a widget the client cannot render says so, rather than
pretending nothing was there.

Two known weaknesses carried over from the server, worth knowing before you
build against this screen:

- **`StatData.value` is a string, and only a string.** The server
  stringifies `Stat::getValue()` once because only the panel's own
  formatting knows whether `"1,340"` should have been `1340` or `1.3k`. You
  cannot do arithmetic on it — a "trend arrow computed on device" feature
  would need the server to publish a second, numeric field, which it does
  not today.
- **No polling or realtime.** The dashboard is exactly as fresh as the last
  `load()`/pull-to-refresh; there is no timer built into `DashboardProvider`
  and none is planned for this screen.

## RTL and i18n

*The panel decides the direction, not the device.*

Every screen this package ships — `PanelIndexScreen`, `ResourceListScreen`,
`ResourceFormScreen`, `ResourceViewScreen`, `RelationListScreen`,
`DashboardScreen` — wraps its own returned widget (the `Scaffold` included,
so the app bar's title alignment and back-button side follow too) in a
`Directionality` resolved from the panel's published `direction`,
**unconditionally, not as a host opt-in**. There is no wiring to do and no
flag to set: a panel whose locale is Arabic renders right-to-left the
moment `/schema` says so, whatever direction the host's own `MaterialApp`
happens to be.

That "unconditionally" is deliberate, not an oversight. Publishing a
capability and leaving the host to wire it has shipped **dead** twice
already in this project — P6d's `fetchRelation`, P6e's `onLinkTap` — each
time caught only in review, because nothing exercises an unwired path until
someone reads specifically for it. Direction is correctness here, not
preference: Arabic labels laid out left-to-right is not a taste a host
might reasonably want to keep. A host whose own app is already RTL sees no
change; a host embedding an Arabic panel inside an LTR app gets the right
answer instead of the wrong one, with nothing to configure.

`ResourceSchema.direction` (and `RelationDescriptor.direction`) are
populated by `PanelSchema.fromJson` at parse time, propagated down from the
one `panel.direction` value into every resource and relation the document
carries. All six screens read direction off data the host already passes
them — not a second value the host would have to thread through — which is
the property that keeps this from being a third capability that ships
published and unwired. A directly-constructed `ResourceSchema`, as in a
test, defaults to `PanelDirection.ltr`.

**Overlay routes get the same wrap, deliberately, not by inheritance.** A
sheet, dialog, picker or dropdown menu pushed from a screen does not
automatically pick up that screen's `Directionality` — `Navigator` mounts a
route's content above the pushing screen in the widget tree, not below it, so
`Directionality` is exactly as invisible to it as any other ordinary
`InheritedWidget` would be outside its subtree. Every route this package
pushes re-wraps itself in the direction resolved from the schema, and each one
has its own test in `rtl_layout_test.dart` asserting the resolved direction at
a widget inside the route — deleting any single wrap reds a named test:

| route | how it re-wraps |
|---|---|
| the list screen's sort sheet | `showModalBottomSheet` `builder:` |
| the record screen's delete confirmation | `showDialog` `builder:` |
| a record action's confirmation | `showDialog` `builder:` |
| a date field's `showDatePicker` | the picker's own `builder:` |
| a datetime field's `showTimePicker` | the picker's own `builder:` |
| a remote select's search sheet | `showModalBottomSheet` `builder:` |
| a select field's dropdown menu | per `DropdownMenuItem`, since `DropdownButtonFormField` has no `builder:` |

A `SnackBar` is deliberately **not** in that list, and the distinction is
worth stating because it is easy to get backwards: a snack bar is not a route.
`ScaffoldMessenger` hands it to the nearest registered `Scaffold`, which
renders it inside its own subtree — already below the screen's wrap — so it
inherits the panel's direction with no help. A wrap was written here anyway,
and measurement showed it was dead code; it was removed rather than left as
untested decoration. The rendered snack bar's direction is asserted directly,
so the day that stops being true, a test says so.

**`textAlign` is finally honoured**, closing the gap P6e's rich text left
open: a `paragraph` or `heading` node renders with the `textAlign` its own
`attrs` carries — `start`/`center`/`end`/`justify`, the server's closed
vocabulary — instead of the value being published and ignored.

**Grouped digit runs are bidi-isolated under RTL**, so a phone number or a
spaced IBAN keeps its own group order inside an Arabic sentence instead of
the bidi algorithm reordering the groups themselves. Measured, not assumed:
a phone number embedded in Arabic prose renders with its digit groups
swapped end-for-end under plain RTL layout, and correctly once wrapped in a
directional isolate (`isolateGroupedDigits`, `lib/ui/bidi_text.dart`). The
pattern it matches is deliberately tight — **two or more digit groups
separated by spaces or hyphens, with an optional leading `+`** — which
catches a phone number, a spaced IBAN, a hyphenated tax number, and
excludes a year, a price (`19.99`; `.` is not a listed separator) or a
plain count, none of which the bidi algorithm reorders internally and none
of which an isolate would fix. A digit is ASCII, Arabic-Indic (`٠`–`٩`,
U+0660–0669) or Extended Arabic-Indic (`۰`–`۹`, U+06F0–06F9): Dart's `\d` is
ASCII-only, and the eastern forms — the numerals an `ar` panel is most likely
to actually contain — reverse with exactly the same measured signature, so
they are matched explicitly.

There is **one implementation, applied at every place this package renders a
server-supplied string** — five call sites, each with its own test asserting
measured glyph order:

| site | what it covers |
|---|---|
| `entries/entry_widgets.dart` (`EntryTile`) | an infolist text entry |
| `semantic_badge.dart` | a badge's label, isolated *after* the colour lookup so the lookup key stays raw |
| `resource_card.dart` (`_text`) | a card's title, subtitle and meta |
| `entries/rich_entry_tile.dart` (`_span`, `_blockNode`) | every rich-text run, plus the two unknown-node fallbacks |
| `dashboard_screen.dart` | a stat tile's value and description |

The implementation is single; the *application* is not, and the difference
matters: a new widget rendering server text has to call the helper, and only a
test at that widget proves it does. The whole-branch review found three of
these five call sites deletable with the entire suite still green — that gap
is what the per-site tests above close.

**This is a heuristic, not a semantic parse — say so plainly.** A free-text
value that happens to be shaped like grouped digits gets isolated too,
whether or not it is actually a phone number. Harmless, since isolation is
the correct rendering for a run shaped like that regardless of what it
means — but it is a guess, and should be treated as one rather than as
proof this package understood the data.

Known weaknesses, stated now:

- **Per-field content direction is not modelled.** Direction follows the
  panel, not the value — a panel whose locale is English but whose data
  happens to be Arabic still lays out left-to-right, because the server has
  no per-value answer to give.
- **Text a host renders itself is not covered.** The isolate runs only
  where this package renders a server-supplied string; a host drawing its
  own widget from the same payload gets the raw, un-isolated string.
- **This package's own `FilamentStrings` are not translated.** They are
  host-supplied with English defaults by design (see Wiring, above) — a
  host serving an Arabic panel supplies Arabic strings itself.
- **Translatable-field editing is untouched.** A `caption.ar` key still
  arrives as a flat sibling beside `caption`, exactly as it always has;
  this slice never touches per-locale field editing.
- **The isolate helper's idempotency guard is whole-string, not
  per-match.** A value that concatenated an already-isolated fragment with
  a fresh, un-isolated run would have the fresh run skipped too — see the
  `ponytail:` comment on `isolateGroupedDigits` for the narrow case this
  leaves unhandled and why a per-match version was tried and reverted.
- **`RichEntryTile` isolates per mark leaf, not per node.** A grouped-digit
  run that a bold boundary splits down the middle — its first group bold,
  the rest plain — arrives as two separate leaves, and neither alone
  matches the pattern, so neither is isolated.
- **The pattern has a leading token boundary but deliberately no trailing
  one.** `(?<!\w)` stops a word ending in a digit from donating its last
  character to the run, so `line1 10 20` isolates `10 20`. There is no
  matching `(?!\w)`, and the asymmetry is measured rather than lazy: a raw
  ISO timestamp still isolates only its date half (`2026-03-24` out of
  `2026-03-24T08:41:19Z`), which changes the relative order of nothing and
  is harmless — while a trailing guard makes it strictly worse, backtracking
  from `2026-03-24` (rejected, `T` follows) to `2026-03` (accepted, `-` is
  not `\w`) and splitting the date itself. Note `\w` is ASCII-only, as `\d`
  was: an Arabic word ending in an eastern numeral is not guarded.

**A note for anyone extending a screen in this package**, hard-won across
three separate fixes in this slice: a `State`'s own `context` — read
outside `build()`, e.g. in a method that opens a dialog, a bottom sheet or
a picker — is an **ancestor** of the `Directionality` that same widget's
`build()` wraps around its returned tree, not a descendant of it. Calling
`Directionality.of(context)` from such a method reads the *host's* ambient
direction, silently ignoring the wrap `build()` installs one line away.
Resolve from the schema value instead, via `textDirectionOf(...)`
(`lib/ui/material_panel_state_builder.dart`), whenever the call site is not
itself inside `build(BuildContext)`.

## Strings

*`FilamentStrings` defaults to English, silently.*

The write path added twelve strings — `save`, `saveFailed`, the four delete
and cancel strings, and the client-side validation hints (eight today:
`fieldRequired`, `fieldEmail`, `fieldUrl`, `fieldPattern`, `fieldConfirmed`,
`fieldColor`, `fieldMin`, `fieldMax`). Every one has an
English default, so a host that upgrades and changes nothing still compiles
and still runs — and shows English hints under server-translated labels.

All eight hints are live against a current server. This client parsed
`url`, `regex` and `confirmed` from the start; the Laravel package's 0.6.0
is the first server that actually publishes and enforces them, closing a
one-sided corner where the parser sat wired and dead. `regex` arrives as
the pattern verbatim and a pattern Dart cannot compile fails open — the
server revalidates regardless, so a hint that cannot even parse is worth
nothing here.

This is sharper than it sounds, because a client hint **blocks the
submission**: when a required field is empty the request never leaves the
phone, so the server's already-translated 422 never arrives and English is the
only thing the user ever sees. Measured on the pilot panel — an Arabic-locale
Filament panel with 33 production resources.
