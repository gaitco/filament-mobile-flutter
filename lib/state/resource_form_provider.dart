import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/options_page.dart';
import '../data/relation_submit_target.dart';
import '../data/resource_data_source.dart';
import '../data/upload_result.dart';
import '../data/write_result.dart';
import '../form/client_validator.dart';
import '../form/form_values.dart';
import '../ports/filament_strings.dart';
import '../ports/filament_transport.dart';
import '../schema/resource_schema.dart';
import '../schema/schema_component.dart';
import 'load_status.dart';

/// Owns one form: its components, its values, its errors, and the `/state`
/// round-trips a `live` field triggers.
///
/// Three rules govern `/state`, each of which has a real bug behind it:
///
/// 1. **Values survive the swap.** `/state` answers with components and no
///    values, so [_components] is replaced and [_values] is never touched by a
///    response. Rebuilding the values from the response resets the form and
///    the user loses what they typed.
/// 2. **Responses are sequenced.** [_stateId] is bumped per dispatch and a
///    response whose id is no longer current is dropped — the guard
///    [ResourceListProvider] already carries, because P1 shipped this exact
///    bug without it.
/// 3. **`/state`'s `hidden` is authoritative**, `/schema`'s is a first-paint
///    hint, so every response overwrites the flag — and a field it reveals
///    keeps whatever the user already typed into it, by rule 1.
///
/// Unlike [ResourceListProvider] this one does own a [Timer]: the debounce
/// belongs to the field that is `live`, which only the provider knows about,
/// and a screen debouncing every keystroke would defeat the point of `live`.
class ResourceFormProvider extends ChangeNotifier {
  ResourceFormProvider({
    required ResourceDataSource source,
    required this.resource,
    required this.strings,
    this.recordId,
    this.submitTarget,
    this.stateDebounce = const Duration(milliseconds: 400),
  }) : _source = source,
       _components = resource.form,
       _values = FormValues.initial(resource.form);

  final ResourceDataSource _source;
  final ResourceSchema resource;
  final FilamentStrings strings;

  /// Null means create. Anything else is the record being edited.
  ///
  /// With a [submitTarget] this is the relation CHILD's id: it seeds the
  /// form through the child resource's own record read, and becomes the
  /// `{child}` segment of the relation update URL.
  final Object? recordId;

  /// Null — every form outside a relation manager — submits to [resource]'s
  /// own endpoints exactly as before. Non-null redirects ONLY the write:
  /// rendering, seeding, `/state` and `/options` all stay on the child
  /// resource, because the child resource's form is what is on screen. This
  /// is the whole write-target override (P9); nothing else about the form
  /// knows it is editing a relation row.
  final RelationSubmitTarget? submitTarget;

  final Duration stateDebounce;

  LoadStatus _status = LoadStatus.initial;
  List<SchemaComponent> _components;
  FormValues _values;
  Map<String, String> _fieldErrors = const {};
  String? _formError;
  String? _errorMessage;
  bool _submitting = false;
  bool _isUnauthenticated = false;
  Timer? _stateTimer;

  /// One sequence per field, because two pickers can be searched independently
  /// and a shared counter would let either cancel the other.
  final Map<String, int> _optionsId = {};
  final Map<String, OptionsPage> _optionsPages = {};
  bool _disposed = false;

  /// Two counters, not one, because the precedence between the two calls is
  /// asymmetric: **a [load] supersedes an in-flight `/state`, but a `/state`
  /// never supersedes a [load]**. They also guard different fields — `/state`
  /// writes [_components], a load writes [_values] and [_status].
  ///
  /// Sharing one counter deadlocks the edit path: a debounce firing during
  /// `load()`'s `await _source.record(...)` would bump the shared id, and
  /// load's own guard would then discard load's own result — [_status] stuck
  /// on `loading` forever, an infinite spinner over a form that never seeds.
  /// [load] bumps *both* (superseding a `/state`), [_refreshState] bumps only
  /// its own (so it can never invalidate a load).
  int _loadId = 0;
  int _stateId = 0;

  LoadStatus get status => _status;
  bool get submitting => _submitting;
  List<SchemaComponent> get components => _components;
  FormValues get values => _values;
  Map<String, String> get fieldErrors => _fieldErrors;

  /// Unmappable `422` keys and save failures — the banner above the form.
  String? get formError => _formError;

  /// The initial load's failure, which is a different screen state entirely:
  /// there is no form to show yet.
  String? get errorMessage => _errorMessage;

  /// True when [load] failed on a 401 — see
  /// [FilamentTransportException.statusCode]. Only the edit path's `record()`
  /// read can trip this; [submit]'s 401 is not mapped here (see [submit]'s
  /// doc).
  bool get isUnauthenticated => _isUnauthenticated;

  /// Seeds the form. Create has nothing to fetch; edit reads the record, whose
  /// `attributes` carry the form's fields since Task 1 of P2.
  Future<void> load() async {
    // A debounce scheduled against the form being replaced is already
    // pointless — it would post the outgoing values and swap in components
    // for a form nobody is looking at any more.
    _stateTimer?.cancel();

    final loadId = ++_loadId;
    // A `/state` response still in flight describes the pre-reload form.
    ++_stateId;

    _status = LoadStatus.loading;
    _errorMessage = null;
    _isUnauthenticated = false;
    // Errors from the submission of a form that is being re-seeded would
    // otherwise sit over values they no longer describe.
    _formError = null;
    _fieldErrors = const {};
    _components = resource.form;
    notifyListeners();

    try {
      final record = recordId == null
          ? null
          : await _source.record(resource.key, recordId!);

      if (loadId != _loadId) return;

      _values = FormValues.initial(
        _components,
        from: record?.attributes ?? const {},
      );
      _status = LoadStatus.success;
    } catch (e) {
      if (loadId != _loadId) return;

      if (e is FilamentTransportException && e.statusCode == 401) {
        _isUnauthenticated = true;
      }
      _errorMessage = messageOf(e);
      _status = LoadStatus.failure;
    }

    _notify();
  }

  /// Records one edit, and asks the server to re-evaluate the form only when
  /// the server itself marked that field `live`. Most forms make zero
  /// round-trips; a provider that called on every keystroke would be the
  /// performance bug `live` exists to avoid.
  void change(String name, Object? value) {
    final previous = _values[name];
    _values = _values.set(name, value);

    // The server's message for this field described the value that was just
    // replaced. Leaving it up would blame the user for the edit they made.
    if (_fieldErrors.isNotEmpty) {
      final next = Map<String, String>.of(_fieldErrors)..remove(name);

      // A repeater's own onChanged always replaces its whole row list, so a
      // row-scoped error ('<name>.<row>.<child>', the same shape
      // `client_validator.dart` and a server 422 both use) is never named by
      // `name` alone and would otherwise survive however many times the row
      // it names gets fixed — this is new with repeater support; no other
      // field produces a dotted error key that `remove(name)` above can't
      // reach. `RepeaterFieldWidget` gives every *untouched* row the same
      // Map instance across an edit (its own row-independence guarantee —
      // see its class doc), so identity alone says which row actually
      // changed, and only that row's stale errors clear — a still-invalid
      // sibling row keeps its error.
      if (previous is List && value is List) {
        for (var i = 0; i < value.length; i++) {
          if (i < previous.length && identical(previous[i], value[i])) {
            continue;
          }
          next.removeWhere((key, _) => key.startsWith('$name.$i.'));
        }
      }

      _fieldErrors = Map.unmodifiable(next);
    }

    if (_isLive(name)) _scheduleState(name);

    notifyListeners();
  }

  /// Uploads bytes for a single-file field and applies the outcome.
  ///
  /// Success goes through [change] — the field's value becomes the stored
  /// path, and any stale error on it clears the same way any other edit
  /// clears one.
  ///
  /// Failure routes on [UploadFailed.statusCode], the same way [submit]
  /// routes a write's `422` by field name: a `422` is *this* field's own
  /// refusal (too large, wrong type) and lands as its error, value
  /// untouched — a failed upload must never clear a file the record already
  /// has. Anything else — a bare 403/500, an offline transport, a host that
  /// never implemented `FilamentUploadTransport` — is not a fact about what
  /// the user picked, so it reaches [formError] instead, same as an
  /// unmappable write failure.
  Future<void> uploadFile(
    String name, {
    required List<int> bytes,
    required String filename,
  }) async {
    final result = await _source.uploadFile(
      resource.key,
      name,
      bytes: bytes,
      filename: filename,
    );

    // Disposal can land during the await — the user backed out of the form
    // mid-upload. Guarded here, where the asymmetry is: both failure
    // branches already notify through _notify(), but success routes through
    // [change], whose bare notifyListeners() asserts on a disposed
    // ChangeNotifier. change() itself stays unguarded on purpose — its
    // other callers are synchronous taps from a live widget, and a
    // silently-no-op change() would hide a real lifecycle bug there.
    if (_disposed) return;

    switch (result) {
      case UploadSuccess(:final path):
        change(name, path);
      case UploadFailed(:final message, :final statusCode)
          when statusCode == 422:
        _fieldErrors = Map.unmodifiable({
          ..._fieldErrors,
          name: message ?? strings.uploadFailed,
        });
        _notify();
      case UploadFailed(:final message):
        _formError = (message == null || message.isEmpty)
            ? strings.uploadFailed
            : message;
        _notify();
    }
  }

  /// Validates client-side first, then writes. Returns true only when saved.
  ///
  /// A 401 here is **not** mapped to [isUnauthenticated]: a transport failure
  /// on write already lands in [WriteFailed] and shows through [formError],
  /// same as any other save failure, and a token that expired mid-edit is a
  /// save the user can retry from the same screen once signed back in — it
  /// is not the "there is no form to show" case [isUnauthenticated] exists
  /// for. Same scope choice Task 5 made for `loadMore()`.
  Future<bool> submit() async {
    if (_submitting) return false;

    _formError = null;
    _fieldErrors = Map.unmodifiable(validate(_components, _values, strings));

    // A hint may only delay a submission by a round-trip; it never reaches the
    // server, so nothing here can forbid what the server would accept.
    if (_fieldErrors.isNotEmpty) {
      notifyListeners();
      return false;
    }

    _submitting = true;
    notifyListeners();

    final payload = _values.payloadFor(_components);
    WriteResult result;
    try {
      final target = submitTarget;
      // One branch, two URL families: the relation target changes WHERE the
      // payload goes, never what it is — validation, the 422 mapping and the
      // banner below are shared verbatim, because the server keys a relation
      // write's 422 by the same child-form field names this screen renders.
      result = target == null
          ? recordId == null
                ? await _source.create(resource.key, payload)
                : await _source.update(resource.key, recordId!, payload)
          : recordId == null
          ? await _source.createRelation(
              target.resourceKey,
              target.recordId,
              target.relation,
              payload,
            )
          : await _source.updateRelation(
              target.resourceKey,
              target.recordId,
              target.relation,
              recordId!,
              payload,
            );
    } catch (e) {
      // create/update return their 4xx as data; only a transport failure
      // throws, and its message is already fit for the user.
      result = WriteFailed(messageOf(e));
    }

    _submitting = false;

    switch (result) {
      case WriteSuccess():
        _notify();
        return true;
      case WriteInvalid(:final errors):
        _applyServerErrors(errors);
      case WriteDenied(:final message) ||
          WriteGone(:final message) ||
          WriteFailed(:final message):
        _formError = message.isEmpty ? strings.saveFailed : message;
    }

    _notify();
    return false;
  }

  @override
  void dispose() {
    // A timer that fires after disposal calls notifyListeners() on a dead
    // provider: it throws in debug and leaks in release.
    _stateTimer?.cancel();
    _disposed = true;
    super.dispose();
  }

  /// Laravel keys its `422` by field name. A key matching no field on this
  /// screen — a rule on a column the form does not show — goes to the
  /// banner rather than into a map nothing renders: an error the user cannot
  /// see is how a form becomes unsubmittable with no explanation.
  ///
  /// "Matching a field" means matching a *renderable* one, so a message aimed
  /// at a hidden or disabled field also reaches the banner instead of a
  /// control that is not on screen.
  ///
  /// A key shaped `'<repeater>.<row>.<child>'` — Laravel's own `422` shape
  /// for a repeater's per-item rules, e.g. `items.0.name` — is the
  /// *authoritative* twin of the row-scoped keys `client_validator.dart`
  /// already produces client-side, so it lands in the same [mapped] map
  /// [FieldState.errors] already reads, not a second path: its first segment
  /// is checked against the writable repeaters on screen, the same "matching
  /// a renderable one" rule above.
  ///
  /// **Exactly three segments**, and that is the renderability test rather
  /// than a formatting nicety: `RepeaterFieldWidget` looks an error up as
  /// `'<name>.<index>.<child>'`, so three is the only depth any widget on this
  /// screen can key into. Layout nesting inside an item template does not
  /// lengthen the path — a `Section`-wrapped child is still `items.*.sku`,
  /// pinned server-side in `RepeaterRulesTest` — and only a NESTED repeater
  /// does. Its key (`outer.0.inner.1.x`) used to be accepted here because the
  /// first segment matched, land in [mapped], and then render nowhere: no
  /// field could key it and the banner never saw it. The user pressed Save,
  /// nothing happened, and nothing said why. Anything deeper now falls
  /// through to the banner unattributed, which is what the banner is for.
  void _applyServerErrors(Map<String, List<String>> errors) {
    final fields = writableFields(_components).toList();
    final names = {for (final field in fields) field.name};
    final repeaterNames = {
      for (final field in fields)
        if (field is RepeaterComponent) field.name,
    };

    final mapped = <String, String>{};
    final unmapped = <String>[];

    for (final entry in errors.entries) {
      // An empty list and a list of empty strings are the same thing to the
      // user: a key that explains nothing. Either way this key cannot be what
      // tells them why the save was refused.
      final message = entry.value.firstWhere(
        (message) => message.isNotEmpty,
        orElse: () => '',
      );
      if (message.isEmpty) continue;

      final repeaterName = entry.key.split('.').first;

      if (names.contains(entry.key)) {
        mapped[entry.key] = message;
      } else if (entry.key.split('.').length == 3 &&
          repeaterNames.contains(repeaterName)) {
        mapped[entry.key] = message;
      } else {
        unmapped.add(message);
      }
    }

    _fieldErrors = Map.unmodifiable(mapped);

    // A 422 whose body was malformed arrives here as an empty map (see
    // `RestResourceDataSource._errorsOf`). Saying nothing would refuse the
    // submission with no visible reason at all.
    _formError = switch (unmapped) {
      [] when mapped.isEmpty => strings.saveFailed,
      [] => null,
      _ => unmapped.join('\n'),
    };
  }

  /// Only a renderable field can be edited, so this doubles as the liveness
  /// lookup — reusing the one shared descent rather than adding a third copy
  /// of it. A `file` field is excluded by that walk and so never goes live;
  /// this build cannot upload one anyway.
  bool _isLive(String name) {
    for (final field in writableFields(_components)) {
      if (field.name == name) return field.live;
    }
    return false;
  }

  void _scheduleState(String changed) {
    _stateTimer?.cancel();
    _stateTimer = Timer(stateDebounce, () => _refreshState(changed));
  }

  /// The options for a select whose list `/schema` refused to inline.
  ///
  /// Carries the form's current values, because options depend on siblings: a
  /// pilot measured a dependent picker narrowing 6 -> 2 -> 1 as its parent
  /// changed, and sending an empty map makes every dependent select wrong.
  Future<OptionsPage> searchOptions(String field, String query) async {
    // Per-field sequencing, the same guard `/state` carries: a search box types
    // fast, and the first response resolving last must be dropped. P1 shipped
    // this bug in ResourceListProvider and it has been guarded twice since.
    final id = (_optionsId[field] ?? 0) + 1;
    _optionsId[field] = id;

    try {
      final page = await _source.options(
        resource.key,
        field: field,
        recordId: recordId,
        values: _values.payloadFor(_components),
        query: query,
      );

      if (_optionsId[field] != id) return _pageFor(field);

      _optionsPages[field] = page;
      _notify();

      return page;
    } catch (e) {
      // Degrade, never block — the same rule `/state` follows. A picker that
      // cannot reach the server shows what it already had; it does not take
      // the form down, and it is deliberately not surfaced in [formError],
      // which is the save banner.
      return _pageFor(field);
    }
  }

  OptionsPage _pageFor(String field) =>
      _optionsPages[field] ?? const OptionsPage.empty();

  /// The options last fetched for [field], empty until one arrives.
  List<SelectOption> optionsFor(String field) =>
      _optionsPages[field]?.options ?? const [];

  Future<void> _refreshState(String changed) async {
    final stateId = ++_stateId;

    try {
      final components = await _source.state(
        resource.key,
        recordId: recordId,
        // The same payload a write would send, so the form is re-evaluated
        // against exactly the state that would be saved. On the edit path the
        // server lays the record's stored values underneath it.
        values: _values.payloadFor(_components),
        changed: changed,
      );

      if (stateId != _stateId) return;

      // Components only. Rebuilding _values from this would wipe the form.
      _components = components;
    } catch (e) {
      // Degrade, never block: the server revalidates on submit regardless, so
      // a failed round-trip costs a conditional field's freshness, not the
      // form. It is deliberately not surfaced in [formError], which is the
      // save banner — the user asked to type, not to fetch.
      if (stateId != _stateId) return;
    }

    _notify();
  }

  /// Disposal can land between an await and its continuation — the user left
  /// the screen while a request was in flight.
  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
