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

## Custom Flutter widgets

Use `FilamentWidgetRegistry` when an application needs to place its own
Flutter UI inside package-owned screens. Register once and pass the registry
to `PanelShell`; the shell forwards it to the dashboard, resource lists,
record views, forms, relation lists, and relation-owned forms:

```dart
final widgets = FilamentWidgetRegistry()
  ..register(
    FilamentWidgetSlot.resourceListBeforeContent,
    (context, scope) {
      final list = scope as ResourceListWidgetScope;
      if (list.resource.key != 'orders') return null;

      return Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Orders are synchronized every five minutes.'),
          trailing: Text('${list.provider.records.length} loaded'),
        ),
      );
    },
  )
  ..registerWidget(
    FilamentWidgetSlot.resourceFormAfterActions,
    const Padding(
      padding: EdgeInsets.only(top: 12),
      child: Text('Changes are written to the audit log.'),
    ),
  );

PanelShell(
  source: source,
  panelProvider: PanelProvider(source),
  widgetRegistry: widgets,
);
```

Multiple builders in one slot render in registration order. A builder may
return `null` to target only one resource or record. Every scope is typed for
its screen and exposes the live provider; record-view scopes also expose the
loaded `ResourceRecord`, and per-dashboard-widget scopes expose the widget and
its index.

The stable placements are:

- panel index: before / after content;
- dashboard: before / after all content and before / after each server widget;
- resource list and relation list: before / after records;
- record view: before entries, before relations, and after all content;
- resource form: before / after fields and before / after the save action.

Pass the same registry directly to an individual screen when composing a
custom shell. Slot widgets live inside the screen's own scrollable content,
inherit its theme and LTR/RTL direction, and adapt with its phone/tablet/desktop
layout. A before/after-content widget can also be the only content of a
successfully loaded but otherwise empty screen. The registry owns placement
only; the host retains normal ownership of the widget's state, callbacks,
services, and visual styling.

## Wide screens

![Phone, tablet and desktop layouts](https://raw.githubusercontent.com/gaitco/filament-mobile-flutter/main/art/wide.png)

The individual screens above are all you need for a phone. On a tablet or
desktop window, `PanelShell` assembles them into one adaptive shell —
drawer (compact, < 600dp) / `NavigationRail` (medium, 600–839dp) / sidebar +
master list + detail pane (expanded, ≥ 840dp) — and keeps the selected
resource and record across a resize:

```dart
PanelShell(
  source: source,
  panelProvider: PanelProvider(source),
  onLogout: () => setState(() => _token = null),
  iconFor: (resource) => switch (resource.key) {
    'products' => Icons.view_in_ar_outlined,
    _ => Icons.folder_outlined,
  },
);
```

That is the whole wiring: no `Navigator.push`, no per-breakpoint layout code.
The example app ([`example/lib/main.dart`](example/lib/main.dart)) runs on
exactly this.

Compose your own shell instead if `PanelShell`'s three-layout assembly does
not fit — the pieces it is built from are public:

- **`FilamentLayout.of(context)`** / **`FilamentBreakpoints`** — the active
  `FilamentFormFactor` (`compact` / `medium` / `expanded`) for a width, so
  your own widget tree can branch the same way `PanelShell` does.
- **`ResourceListScreen(rowStyle: ListRowStyle.row, selectedRecordId: ...)`**
  — a header row plus dense table rows instead of cards, with one row
  highlighted for whatever the adjacent detail pane is showing. Unset, the
  style follows the form factor: cards on a phone, rows on anything wider.
  A row drops its date column below 560dp and its badges below 300dp rather
  than clipping them, so a narrow pane still reads.
- **`maxContentWidth`** on `ResourceViewScreen`, `ResourceFormScreen` and
  `DashboardScreen` — each caps and centres its content by default on a wide
  viewport; pass a value (or `double.infinity`) to override it. Lists get an
  always-visible scrollbar on a non-compact viewport.
- **`ResourceFormScreen(onSaved: ...)`** — fires after a successful save
  instead of only popping the route, for a host that keeps the form in
  place (a detail pane) rather than pushing it.

Override the breakpoints by passing your own `FilamentBreakpoints` to
`PanelShell` (or to a `FilamentLayout` you install yourself):

```dart
PanelShell(
  source: source,
  panelProvider: panelProvider,
  breakpoints: const FilamentBreakpoints(medium: 720, expanded: 1024),
);
```

## What ships

| Feature | What you get |
|---|---|
| [Custom widgets](#custom-flutter-widgets) | Host-owned Flutter widgets in stable named positions across every screen |
| [Wide screens](#wide-screens) | `PanelShell` — drawer / rail / sidebar + master-detail, by form factor |
| [Actions](#actions) | Buttons the server already authorised for this record |
| [Filters](#filters) | A sheet and indicator chips off the server's published filters, with a badge showing how many are active |
| [Upload](#upload) | Single- and multi-file upload, through an additive port your existing transport need not implement |
| [Repeater](#repeater) | Add and remove rows, validated per row |
| [Radio](#radio) | Real radio buttons, parsed off `select`'s own model |
| [Toggle buttons](#toggle-buttons) | Chips — one choice or many, off `select`'s option shape |
| [Slider](#slider) | Material `Slider` / `RangeSlider`, divisions from the published step |
| [Tags](#tags) | Chips with a remove affordance, always a `List<String>` |
| [Maps and phone numbers](#maps-and-phone-numbers) | Built-in verbatim phone editing; opt-in interactive maps through `filament_mobile_maps` |
| [Translatable](#translatable) | One field, locale chips — instead of a stacked field per locale |
| [Key/value](#keyvalue) | Add/remove pairs, key and value cells gated independently |
| [Colour](#colour) | A text field with a live swatch, in the panel's own format |
| [Time and date bounds](#time-and-date-bounds) | `showTimePicker`, and the bounds a picker declares |
| [Relations](#relations) | A child list on the record screen — writable when the server names a child resource; "See all" opens the full paginated view, with search and sort where the server declares them |
| [Rich text](#rich-text) | A real document — headings, lists, quotes, emphasis, links |
| [Schema caching](#schema-caching) | Cold start renders from cache, revalidates behind it |
| [Background refresh](#background-refresh) | Lifecycle-aware polling plus an optional host-owned realtime adapter |
| [Dashboard](#dashboard) | Stat tiles render; charts drawn by the opt-in [`filament_mobile_charts`](https://pub.dev/packages/filament_mobile_charts) sibling, or your own builder |
| [RTL and i18n](#rtl-and-i18n) | Panel direction plus explicit field/entry overrides |

Everything below is reference. Each feature section ends with a **Known
weaknesses** list stating plainly what it does not do.

## Field types this client renders

![Form field types](https://raw.githubusercontent.com/gaitco/filament-mobile-flutter/main/art/inputs.png)

The core package has built-in widgets for these form types:

`text` · `textarea` · `email` · `password` · `number` · `select` ·
`multiselect` · `radio` · `toggle_buttons` · `slider` · `toggle` ·
`checkbox` · `date` · `datetime` ·
`time` · `color` · `file` · `tags` · `keyvalue` · `repeater` · `phone`

Infolist entries render through `EntryRegistry`: `text_entry`,
`badge_entry`, `boolean_entry`, `image_entry` and `rich_entry`. An
entry-typed node reaching a *form* — the server's `Placeholder` publishes as
`text_entry` — renders nothing: entries belong to infolists, and the field
registry's fallback arm is a `SizedBox.shrink()`.

`map_point` and `map_point_entry` are parsed in core but rendered by the
optional [`filament_mobile_maps`](https://pub.dev/packages/filament_mobile_maps)
companion. Without it they show a visible extension-required card instead of
silently disappearing.

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

## Maps and phone numbers

`phone` is built into core. It uses `TextInputType.phone`, preserves the
server's stored string verbatim, and displays a field-keyed 422 from the phone
plugin. The published format and country values describe the panel; core does
not reformat, validate locally, or add a country picker.

Maps stay optional so applications that do not use them keep the core
package's two-dependency floor. Install and register the companion once:

```bash
flutter pub add filament_mobile_maps
```

```dart
final fields = FieldRegistry.defaults()
  ..register('map_point', mapFieldBuilder());
final entries = EntryRegistry.defaults()
  ..register('map_point_entry', mapEntryBuilder());

PanelShell(
  source: source,
  panelProvider: panelProvider,
  fieldRegistry: fields,
  entryRegistry: entries,
  widgetRegistry: widgets, // optional host-owned content slots
);
```

The map renderer honours the server's pan/tap gates, marker, camera bounds,
tile template, and attribution. Attribution remains visible even when the
server omitted it. The map builders use the same registries as every custom
field/entry renderer; `FilamentWidgetRegistry` remains available independently
when the host also wants to place arbitrary Flutter widgets before or after
package content.

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

## Filters

*A sheet, indicator chips, and the count badge — driven by `/schema`'s
`filters` array, never a client-side guess at what the server can narrow.*

A resource's published filters (`ResourceSchema.filters`, a `List<
SchemaComponent>` shaped exactly like a form select) drive `FilterSheet`
(`lib/ui/filter_sheet.dart`), opened from a filter `IconButton` beside the
sort action on `ResourceListScreen` — hidden when `resource.filters` is
empty, exactly like the sort action is hidden with no sorts. The button
carries a `Badge` showing `ResourceListProvider.activeFilterCount` (an
already-cleared filter — `''`, `null`, or an empty `List` — does not count)
whenever it is greater than zero.

The sheet renders one `SelectFieldWidget` per filter against
`provider.filters[name]` / `provider.setFilter(name, value)`, plus a "Clear
all" button (`provider.clearFilters()`). A single-value (non-`multiple`)
filter gets a synthetic "Any" option prepended, so a filter with no explicit
value still reads as a real selection rather than a blank field; picking it
calls `setFilter(name, null)` — an explicit clear, not merely "no choice
made". A `->multiple()` filter's own empty-selection state already serves
that purpose, so no "Any" is prepended for it.

Above the list, one `InputChip` per **active** filter (a chip only appears
once its value differs from cleared) shows the matching option's label —
or, for a multiselect, its selected labels joined — with a delete affordance
that clears just that filter (`setFilter(name, null)`), leaving the others
untouched.

`ResourceListProvider.filters` seeds every published filter's own
`->default()` on construction, so a resource whose filter carries a default
starts pre-narrowed on first load, matching what the panel itself would
show a fresh visitor — call `clearFilters()` to see the unfiltered list.

When a filter publishes `optionsUrl`, the same remote picker used by form
selects opens with loading, empty, failure/retry and `hasMore` states. A
single filter receives the same synthetic "Any" option as an inline one;
remote multiselect keeps the sheet open while choices are toggled and commits
them together with Save. `RestResourceDataSource` implements the optional
`FilterOptionsDataSource` capability. Existing custom data sources remain
source-compatible; they can opt in to remote filters by implementing it.

## Upload

*The host supplies the transport and the picker.*

A `FileUpload` field — single or `->multiple()` — is editable from the
phone, through two
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
for (one whose constraints or `multiple()` closure throws
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

### A multiple field is N uploads, not one

A `file` node with `config.multiple: true` renders as a list of rows — one
per stored path, filename basenames, a per-item remove — plus an add
button. Each add tap is the same pick-then-upload loop as single-file: one
pick through the same `filePicker` (which still returns a single
`PickedFile`), one `uploadFile()` call, then the returned path is appended
to the field's `List<String>` value. The endpoint never sees more than one
file per request; the list is assembled client-side and submitted whole on
save — wholesale-replacement, so removing a row means the submitted list
simply no longer contains that path, and submitting an empty list clears
the column.

The add button stops being offered once the list reaches `maxFiles` — a
**hint**, the repeater-cap idiom: the server's array `max` is the rule, and
a crafted over-count submission 422s regardless of what the widget showed.
The same in-flight guard applies per pick, so a slow upload cannot be
double-fired. All the single-file fallbacks carry over unchanged: no
`filePicker` or no upload-capable transport and the field is read-only with
the honest note, and a server-published `readOnly` always wins.

A scalar arriving under a `multiple: true` field (an older server, a
hand-written payload) is tolerated on read rather than crashing the form —
but on write the value is always a list.

### Known weaknesses, carried from the server or inherent to the port

- **Orphaned files accumulate.** A user who picks a file and abandons the
  form leaves a stored file with no row pointing at it — and a multiple
  field makes this more frequent, not different: one abandoned form can
  strand a whole list. This package does
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
- **No reordering of a multiple field's list.** The widget renders list
  order and offers no drag affordance — same stance as the repeater's
  `reorderable`.

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

## Toggle buttons

*Chips, parsed off `select`'s own option shape — one choice, or many when
`multiple`.*

A `toggle_buttons` node parses into `ToggleButtonsComponent` — the same
flattened `SelectOption` list a `select`/`radio` node carries, plus an
always-present `multiple` (absent or wrong-typed reads as `false`, the
degradation rule every other config key already follows) — and renders
through `ToggleButtonsFieldWidget`: a `ChoiceChip` per option when
`multiple` is false, a `FilterChip` per option when true. The value is a
scalar or a `List` accordingly — the `select`/`multiselect` split — through
the ordinary form-state and write paths. A node never carries
`config.optionsUrl`, so there is no search affordance to render, and the
widget lays out however many options arrive. `state.enabled` and the
server's `readOnly` are both honoured.

### Known weaknesses, stated now

- **Per-option colors, icons, tooltips and disabled state are not on the
  wire.** A disabled option is the server's `in:` rule to refuse, not a
  client rendering to reproduce.

## Slider

*A Material `Slider`, or a `RangeSlider` when `multiple`; divisions come from
the published `step`.*

A `slider` node parses into `SliderComponent` (`min`/`max` always present —
absent reads as `0`/`100`, Filament's own accessor defaults; `step` only when
the server published a numeric one; `multiple` always present) and renders
through `SliderFieldWidget`. There is **no slider-specific validation**:
`Slider::setUp()` force-registers `numeric`/`min:`/`max:` server-side, and
those arrive as the node's ordinary `rules`, which the client already
pre-validates. Both Material widgets *assert* on contradictory bounds and on
a value outside them, so the widget clamps rather than trusting the payload —
a stored value outside the published range reads as the bound, never a crash.

**`multiple` is a hint, never a gate.** The server detects range mode from
the state being an array, and on `/schema` that means an array `->default()`
— a range slider with no array default publishes `multiple: false` while its
rules still say `array` (a documented server weakness, see
`contract/README.md`'s Slider section). The widget renders from whatever the
node currently says — `/state` can re-answer — and never blocks a submission
on the hint; a `422` keyed to the field lands on the field as usual.

### Known weaknesses, stated now

- **Pips, tooltips, behavior, fillTrack, vertical, rtl, nonLinearPoints,
  minDifference/maxDifference and decimalPlaces are not on the wire**, so the
  phone may offer a value the web panel's own controls would not — the
  enforced bounds are the published `rules`, which are complete.
- **A string `step` arrives as no `step` at all** — absence means "any step",
  so the control renders without divisions.

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

## Translatable

*A `caption.ar`/`caption.en` pair renders as one field with locale chips,
not two fields stacked under "Ar"/"En" labels.*

`ResourceFormScreen`'s node walk groups every `translatable: true` leaf by
the head of its dotted name (`caption.ar` and `caption.en` both group under
`caption`) into a single field slot:

- **Group label** is the humanized head attribute — `caption`, not the
  useless per-locale label a stacked field used to carry.
- **A chip row** sits above the field, one chip per locale, labelled with
  the UPPERCASED locale code parsed off the tail of the field's own name
  (no `intl` dependency). Chips order by `panel.locales` when the host
  wired that list in and it is non-empty, else by the fields' own
  appearance order.
- **The chip only selects which member renders.** Every member's value
  stays in `FormValues` regardless of which chip is selected, and the
  submitted payload still carries every locale — submission logic does not
  change at all, which is what keeps the server's merge guarantee true.
- **A 422 keyed to a non-visible member force-switches the chip to it** —
  the official web plugin's own rule. An error must never hide behind a
  chip the user has not selected.
- **A group of exactly one locale renders chipless**, exactly as a single
  dotted field always has.
- A non-translatable dotted field, and the scalar sibling beside a
  translatable one, render exactly as they do today — the group only forms
  around leaves the server actually marked `translatable`.

### `panel.locales` reaches the form with no host wiring

`ResourceSchema.locales` is populated by `PanelSchema.fromJson` at parse
time, propagated down from the one `panel.locales` value into every
resource the document carries — the same mechanism `ResourceSchema.direction`
already uses (see RTL and i18n, below). `ResourceFormScreen` reads
`widget.provider.resource.locales` straight off the resource its own
provider already holds; there is no `locales` constructor parameter to
wire up, and there never needs to be one. A directly-constructed
`ResourceSchema`, as in a test, defaults to `const []` (appearance order).

### Degradation, both directions

- **Old server (no `translatable` annotation at all).** No group ever
  forms — every dotted locale field renders as its own stacked field,
  labelled by its own name, exactly as it does today. Nothing in the
  parsing or the form screen changes behaviour for a document that never
  publishes the key.
- **New server, old client.** `SchemaComponent.translatable` is an
  unrecognised JSON key to a client built before this feature, and is
  simply never read — the fields still parse and render as ordinary
  stacked dotted fields. The old client works unchanged against a new
  server; it just does not get the chip grouping.

### Known weaknesses, stated now

- **No locale display names.** Chips show the raw locale code, uppercased
  — `AR`, not "Arabic" — matching this package's stance of not taking an
  `intl` dependency for this slice.
- **Per-locale direction is explicit, never guessed.** A node carrying
  `direction: rtl|ltr` overrides the panel for that field or entry; absence
  inherits. Declare the matching Filament `dir` attribute on each locale
  field—the client deliberately does not maintain a locale-direction table.
  The wrapper lives at `FieldRegistry`/`EntryRegistry`, so host-custom
  builders receive a context already under the override too.
- **Editing an official-plugin field per locale is out of scope.** An
  undotted field the plugin swaps by panel locale stays single-locale on
  mobile; see the Laravel README's Translatable section and its `doctor`
  diagnostic.

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
- **All four gates are server-enforced too.** The client still omits each
  forbidden control so an ordinary user never discovers the rule through a
  422. The Laravel write path also compares trusted defaults/stored values
  and rejects crafted additions, removals, existing-value edits, or ambiguous
  renames. A restricted KeyValue inside a repeater makes that owning repeater
  read-only because its rows have no stable wire identity. See the Laravel
  README's Key/value section for the exact matrix.

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

**Steps are parsed, and deliberately not acted on.** `DateComponent` reads
`hoursStep` / `minutesStep` / `secondsStep` — absent or wrong-typed reads as
1, the vendor default — but the widgets ignore them: the stock Material
pickers have no step grid, the server enforces no step, and snapping or
rejecting a picked time would make mobile stricter than the web panel it
mirrors. The keys exist for a host rendering its own picker.

### Known weaknesses, stated now

- **Bounds are hints — final ruling, by web parity.** The web panel does not
  enforce `minDate`/`maxDate` server-side either, so mobile must not be
  stricter than the panel it mirrors; the picker's clamp is the enforcement.
  The server refuses an out-of-range value only if the panel declared a rule
  saying so.
- **A `seconds` field resets seconds when the time changes.** They are
  preserved when the hour and minute are untouched; a genuinely new time starts
  at `:00`, because welding a stale `:30` onto a newly picked 16:20 would be a
  time nobody chose.
- **Disabled dates and first-day-of-week are not published — final, not
  deferred.** A `disabledDates` list is closure-evaluated at schema-build time
  and would freeze behind the server's ETag cache, silently stale; the stock
  Material date picker derives the first day of week from the device locale and
  takes no parameter, so there is nothing to honour it with. Both are
  documented rejections, not backlog.

## Relations

*A labelled section on the record screen; "See all" opens the full list.*

![Relation writes](https://raw.githubusercontent.com/gaitco/filament-mobile-flutter/main/art/relations.png)

`ResourceSchema.relations` (`List<RelationDescriptor>`, **always present** —
`[]` when the server publishes none, and read the same way on an *absent*
`relations` key: a server predating this feature) is what a resource's
Filament relation managers become on mobile. Filters stay out; search and
sort are host-declared per relation on the server and arrive on the
descriptor (below) — see the Laravel README's Relations section for the
full server picture, including why a relation manager that narrows its own
query is not published at all. Against a current server a relation can also
be **writable**, which is what its descriptor's `resource` key announces.

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

Since P11 the descriptor also carries **`search`** (the resource level's
`ResourceSearch`, reused) and **`sorts`** (`List<ResourceSort>`, reused),
with a **`defaultSort`** getter — the same shapes `ResourceSchema` already
parses, and the same readings: an absent or wrong-typed key means a server
predating P11 and reads as disabled / `[]`, never a throw. A pre-P11 server
is indistinguishable from an undeclared relation, which is exactly what the
wire shape intends.

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
    String? search,
    String? sort,
    String? direction,
  });
}
```

**P11 widened this signature — breaking for a host with its own
`ResourceDataSource` implementation**, which must add the three optional
named parameters to compile; it is source-compatible for callers, and a
host on `RestResourceDataSource` needs no change at all. The REST
implementation builds the query string with the same omission rule as
`list()`: an unknown sort key is a `422` on the relation endpoint too, so
nothing is sent that the server has not declared.

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
same seam the section widget uses. Since P11 it also mirrors
`ResourceListProvider`'s search/sort behaviour exactly: `searchTerm` /
`activeSort` state with `search()` / `sortBy()` methods (each refetches
from page one — the list's own reset, not a new page), and the descriptor's
declared `defaultSort` active from the first fetch. `RelationListScreen`
mirrors `ResourceListScreen`'s skeleton, scroll pagination and
`PanelViewState` mapping, reusing the same
`CardListSkeleton`/`PaginatedCardList` widgets both screens share, and draws
a **search field and sort sheet gated on `relation.search.enabled` /
`relation.sorts.isNotEmpty`** — nothing drawn for an undeclared relation or
a pre-P11 server, mirroring `ResourceListScreen`'s own gating. The screen's
title is the relation's own `label`.

**`RelationSectionWidget` — the embedded section on the record screen —
stays plain, deliberately**: no search field, no sort control there. List
controls live on the full screen; the section is a preview with a "See
all".

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
- **The relation manager's own filters stay ignored, and its table's
  search/sort are never read.** Undeclared, the list arrives in relation
  order, unfiltered — matching the server exactly, which itself never
  introspects the manager's table. Search and sort appear only where the
  host declares them per relation; a pre-P11 server reads as undeclared.
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

## Background refresh

When the server publishes `panel.poll`, `PanelShell` automatically applies its
intervals to resource lists, record views, and the dashboard. Individual
screens also read the interval carried by their `ResourceSchema`; a standalone
`DashboardScreen` accepts `pollInterval` explicitly.

Polling is conservative by design:

- each timer has ±10% jitter and no two reads for one screen overlap;
- covered routes and backgrounded apps do no work;
- resource lists pause while drag-to-reorder is active;
- returning to the foreground triggers one prompt revalidation;
- transient background errors leave the last good content visible, while a
  401 still becomes an authentication failure.

`RestResourceDataSource` uses `FilamentConditionalTransport` when the host
already supplies it. It keeps the last response and ETag in memory for each
list query, detail record, and dashboard request; a 304 reuses that parsed
body. A conditional 304 without a cached body safely falls back to an ordinary
GET. A host with only `FilamentTransport` remains compatible and performs a
normal GET on each interval.

No `panel.poll` member means no timers, preserving the old behavior. The app
requires no Reverb client or persistent background service unless the host
chooses to provide one.

For realtime invalidation, implement `FilamentEventTransport` over the
Pusher-protocol client already selected by the application and pass it to
`PanelShell(eventTransport: events)`. After loading the panel schema, configure
that client from `panel.realtime`, authenticate each logical resource channel
through its `authEndpoint`, and map `filament-mobile.changed` to
`RealtimeEvent.changed`. Emit `RealtimeEvent.reconnected()` after a successful
reconnect. Cancelling the stream returned by `events(channel)` must release
that private-channel subscription; the host continues to own the shared
socket itself.

The socket carries invalidation hints only. Screens coalesce bursts and then
use their existing authorized HTTP provider, so no event payload is rendered
directly. List refreshes revalidate page 1 while preserving the current scroll
position. Detail and dashboard keep their last successful content during a
transient refresh failure. When both `panel.realtime` channels and
`panel.poll` are available, push replaces the ordinary cadence and polling
continues at 4× the declared interval as a quiet-connection watchdog. Surfaces
without a usable adapter or channel keep the normal polling cadence.

Include the socket client's current id as `X-Socket-ID` on mobile HTTP writes
to prevent a successful local mutation from causing a duplicate refetch.

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

## Notifications

The in-app bell (P21). `PanelShell` draws it in the dashboard AppBar under
a double gate: the panel declared `panel.notifications` **and** the data
source implements `NotificationsDataSource` — a control the host cannot
serve is never drawn, the `filePickerUnavailable` principle.
`RestResourceDataSource` implements it already, so a REST host gets the
bell by flipping the server config; a custom data source opts in by
implementing the sidecar interface (kept outside `ResourceDataSource`, the
`FilterOptionsDataSource` precedent, so existing implementations do not
break):

```dart
class MySource implements ResourceDataSource, NotificationsDataSource { ... }
```

The badge refreshes through the same seam as every other screen (P20):
polling at the published interval — 30 seconds by default, one ETag'd
request that is a ~200-byte 304 when nothing changed — and, when the panel
also publishes the user's private notification `channel` and the host
supplied a `FilamentEventTransport`, push replaces the cadence with the
usual 4× watchdog. Forward any event on that channel as an invalidation;
the fields are unused (Filament's `database-notifications.sent` carries an
empty payload by design).

Tapping the bell opens the feed — a bottom sheet on compact, a dialog on
medium/expanded, panel-`Directionality` re-applied inside like every
overlay. Row tap marks it read; the header offers mark-all-read and a
confirm-gated clear-all (it deletes read and unread alike — the web
bell's own semantics); each row can be dismissed; a notification's
url-carrying actions render as buttons only when the host wired
`onLinkTap`, the rich-text link rule. Timestamps are relative for the
recent past ("3 hours ago", localized through `FilamentStrings`) and fall
back to an absolute date beyond 30 days — no intl dependency.

The feed shows the first page of notifications; sending happens entirely
server-side through Filament's own `sendToDatabase`, and this package adds
no push notifications — APNs/FCM is a later, separate slice.

## Dashboard

*Stats render; charts come from the opt-in sibling package, or your own builder.*

![Dashboard and charts](https://raw.githubusercontent.com/gaitco/filament-mobile-flutter/main/art/charts.png)

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
- **No socket push.** When the server publishes `panel.poll`, the dashboard
  revalidates on that interval; otherwise it remains exactly as fresh as the
  last `load()`/pull-to-refresh. Reverb/WebSocket delivery is not part of this
  phase.

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

**A named field or entry may override that inherited answer.** The optional
node-level `direction` parses to `ComponentDirection.ltr|rtl`; absence or an
unknown value remains null and inherits the panel. `FieldRegistry` and
`EntryRegistry` install the override before calling their built-in switch or a
host-registered builder, so custom widgets can read the correct
`Directionality` directly from the callback context. Repeater children pass
through the same registry and may each override independently.

Laravel publishes this from Filament's own `dir` attribute rather than
guessing from content or locale. For a bilingual group, declare
`extraInputAttributes(['dir' => 'rtl'])` on `caption.ar` and `ltr` on
`caption.en`; an undeclared member continues to follow the panel.

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

- **Direction is declared, not inferred from content.** An English panel with
  undeclared Arabic data still lays that field out LTR. Publish the field's
  `dir` attribute when its semantic direction differs from the panel; the
  package deliberately does not guess from text or maintain a locale table.
- **Text a host renders itself is not covered.** The isolate runs only
  where this package renders a server-supplied string; a host drawing its
  own widget from the same payload gets the raw, un-isolated string.
- **This package's own `FilamentStrings` ship in English and Arabic only.**
  They are host-supplied with English defaults by design (see Wiring, above);
  `FilamentStrings.arabic()` covers the Arabic case, and a host serving any
  other language supplies its own strings.
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

## UI language picker

*The shell offers the switch; the host owns everything the switch does.*

`PanelShell` can put a language picker in its profile menu (P22):

```dart
PanelShell(
  // ...
  strings: FilamentStrings.forLocale(localeTag),
  languages: const [
    FilamentLanguageOption('en', 'English'),
    FilamentLanguageOption('ar', 'العربية'),
  ],
  activeLanguage: localeTag,
  onLanguageSelected: (tag) => /* persist tag, rebuild with it */,
)
```

The entries render only when the host wired `onLanguageSelected` **and**
offered at least two languages — one language is nothing to switch to, and a
list without a callback would draw a control that does nothing when tapped,
the same principle as `filePickerUnavailable`. Each option's label is an
endonym the host supplies ("العربية", not "Arabic"): a language naming
itself reads the same whichever language is currently active, so the labels
are deliberately never translated by this package.

The shell holds **no language state of its own**. A tap reports the chosen
tag and nothing else changes until the host acts: swap `strings` (usually
`FilamentStrings.forLocale`), set the `MaterialApp` locale so text
direction and Flutter's own widget strings follow, persist the tag so the
choice survives a relaunch, and pass it back as `activeLanguage` — the
check mark in the menu is the host's word, not an echo of the last tap.
Persistence is per device and entirely the host's: the package takes no
storage dependency, exactly as it takes no HTTP one. The example app wires
all of this end to end with `shared_preferences` at its root — see
`example/lib/main.dart`.

This is the *UI* language only, deliberately. The panel's content — labels,
options, validation messages — already arrives translated in the panel's
locale, and the panel's published `direction` keeps deciding how package
screens lay out (see RTL and i18n above); neither is renegotiated by the
picker, and no request is sent because of it.

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

**Arabic ships with the package.** `FilamentStrings.arabic()` returns every
field above in Modern Standard Arabic, matching Flutter's own Material
localisations where it has a canonical word (Cancel = إلغاء, Delete = حذف,
Save = حفظ, Retry = إعادة المحاولة, Search = بحث) — including the
parameterised closures, with each bound placed where Arabic word order wants
it. It is a factory, not a `const`: a closure capturing its bound is not a
compile-time constant, so the one call site per screen pays a small
allocation instead of gaining a second, subtly different, strings type.

For the common case the wiring is one call: `FilamentStrings.forLocale`
takes a locale tag — typically `panel.locale`, already in hand wherever a
screen is built — and returns the Arabic instance for any `ar*` tag
(case-insensitive: `ar`, `ar-SA`, `AR` alike, since the translations are
Modern Standard, not a regional variant) and the English defaults for
anything else, including null. Hosts serving other languages are unaffected:
they construct and pass their own `FilamentStrings`, exactly as before —
`forLocale` is a convenience, not a registry this package means to grow. The
companion `filament_mobile_charts` package mirrors both members on
`FilamentChartStrings`, for its two fallback messages.

## Status & roadmap

The package is production-released and in daily use; everything documented
above is shipped and tested (1000+ tests on each side, CI against Filament 4
and 5). In short, what already works end to end:

- Panel index, lists (search, sort, filters, pagination), record view,
  create/edit/delete, per-record actions.
- Some thirty field and entry types, including repeater, single/multi file
  upload, tags, key/value, slider, toggle buttons, colour, date/time bounds,
  map points and phone numbers.
- Relations: read, search/sort, and row create/edit/delete.
- Dashboard stats and charts, adaptive tablet/desktop layout (`PanelShell`),
  RTL and i18n, schema caching, background refresh (polling + ETag, with a
  socket-neutral realtime seam).
- Host extension points: `FieldRegistry`/`EntryRegistry`,
  `FilamentWidgetRegistry`, and the `filament_mobile_charts` /
  `filament_mobile_maps` companion packages.

What is next, in rough priority order — help welcome on any of it:

- **Push notifications (APNs/FCM)** — the in-app bell shipped; delivering
  its feed while the app is closed is the natural next slice.
- **Rich-text editing on the client.** Rich content renders today and edits
  as a plain textarea; a real mobile editor is the largest open item.
- **Repeater gaps**: `live()` reactivity inside rows, nested repeaters, and
  row reordering.
- **Locale-aware value formatting** on entry widgets (dates, numbers).
- **Pivot attach/detach** for BelongsToMany relations — row create/edit/
  delete works; attaching an *existing* record does not.

Deliberately out of scope — please do not propose them: a login/auth flow
(the host app owns authentication and hands this package a transport), bulk
actions, and `TableWidget` / arbitrary Blade or Livewire views (no data
contract to read).

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md)
for how this repository relates to the private monorepo it is a snapshot of,
how to run the suite locally, and the ground rules that trip newcomers.
