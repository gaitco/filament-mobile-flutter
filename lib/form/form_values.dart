import '../schema/schema_component.dart';

/// A form's in-progress values.
///
/// Runtime-shaped like [ResourceRecord]: the schema is only known at runtime,
/// so this is a typed wrapper over a map rather than a generated model. It is
/// immutable — [set] returns a new instance — so a provider's
/// `notifyListeners()` always corresponds to a genuinely new object and a
/// widget comparing old to new sees a difference.
class FormValues {
  const FormValues._(this._values, this._dirty);

  /// Seeds one value per named field in [components]: [from] (a record being
  /// edited) wins when it holds the key — including an explicit `null`, which
  /// is a value the user deliberately cleared — and a component's own
  /// `default` fills the gap only when [from] has no entry at all.
  factory FormValues.initial(
    List<SchemaComponent> components, {
    Map<String, dynamic> from = const {},
  }) {
    final values = <String, Object?>{};
    for (final field in _leaves(components)) {
      final name = field.name!;
      values[name] = _hasPath(from, name)
          ? _readPath(from, name)
          : _defaultOf(field);
    }
    return FormValues._(Map.unmodifiable(values), const {});
  }

  final Map<String, Object?> _values;
  final Set<String> _dirty;

  Object? operator [](String name) => _values[name];

  /// Over-eager on purpose: setting a field back to its initial value still
  /// marks it dirty rather than diffing against the seed. An extra field in
  /// the payload is cheap; silently dropping a real edit is not.
  FormValues set(String name, Object? value) {
    return FormValues._(
      Map.unmodifiable(Map<String, Object?>.of(_values)..[name] = value),
      Set.unmodifiable({..._dirty, name}),
    );
  }

  Set<String> get dirty => _dirty;

  /// Builds a submission payload from the schema's declared field names, not
  /// from [_values]'s keys — the client-side mirror of the server's "no rule,
  /// no validated key, no write". A key the schema does not declare, however
  /// it got into the value map, can never reach the server this way.
  ///
  /// A name is included only when it is genuinely writable: not hidden, not
  /// disabled, and not a **read-only** [FileComponent] — a multiple (or
  /// gated) file field the server marked `readOnly` still has nowhere for a
  /// client-sent value to go, so submitting one is noise at best. A
  /// single-file field the server left writable is different: by the time a
  /// submit happens its value, if set, is already the path `/upload`
  /// returned (see `ResourceFormProvider.uploadFile`), and the server
  /// expects that path in the payload like any other field.
  /// A dotted name is a **path**, not a literal key: Laravel validates
  /// `title.ar` against `title[ar]`, and a translatable Filament field is
  /// published with exactly that name. Sending `{"title.ar": …}` flat makes
  /// every such field read as absent, so a filled form comes back 422
  /// "required" on the fields the user just typed into.
  Map<String, dynamic> payloadFor(List<SchemaComponent> components) {
    final payload = <String, dynamic>{};
    for (final field in writableFields(components)) {
      _writePath(payload, field.name!, _values[field.name!]);
    }
    return payload;
  }

  /// Walks [components], descending into every container so a nested field
  /// is never missed, and yields the named leaf fields — the only nodes that
  /// hold a value. Unaware of hidden/disabled: a field still needs a seeded
  /// value even while hidden, since a `live` toggle elsewhere can reveal it
  /// later.
  static Iterable<SchemaComponent> _leaves(
    List<SchemaComponent> components,
  ) sync* {
    for (final component in components) {
      switch (component) {
        case LayoutComponent(:final children):
          yield* _leaves(children);
        case UnknownComponent(:final children):
          yield* _leaves(children);
        default:
          if (component.name != null) yield component;
      }
    }
  }

  /// The component's own `default`, for the subtypes that parse one.
  ///
  /// [FileComponent] and [EntryComponent] never carry a value to seed. Nor
  /// does [UnknownComponent] — its parser doesn't capture `default` at all,
  /// so an unknown leaf field type loses its default here; see the task
  /// report.
  static Object? _defaultOf(SchemaComponent component) {
    return switch (component) {
      TextComponent(:final defaultValue) => defaultValue,
      NumberComponent(:final defaultValue) => defaultValue,
      SelectComponent(:final defaultValue) => defaultValue,
      ToggleButtonsComponent(:final defaultValue) => defaultValue,
      SliderComponent(:final defaultValue) => defaultValue,
      BooleanComponent(:final defaultValue) => defaultValue,
      DateComponent(:final defaultValue) => defaultValue,
      ColorComponent(:final defaultValue) => defaultValue,
      _ => null,
    };
  }
}

/// Laravel treats a dotted field name as a path into nested data — a
/// translatable Filament field is published as `title.ar` and validated
/// against `title[ar]` — so the three helpers below read and write a value
/// map the same way. Each keeps a literal-key fast path first, so a server
/// that really does send a flat dotted key still resolves.
bool _hasPath(Map<String, dynamic> source, String path) {
  if (source.containsKey(path)) return true;
  if (!path.contains('.')) return false;

  Object? node = source;
  for (final segment in path.split('.')) {
    if (node is! Map || !node.containsKey(segment)) return false;
    node = node[segment];
  }
  return true;
}

Object? _readPath(Map<String, dynamic> source, String path) {
  if (source.containsKey(path)) return source[path];

  Object? node = source;
  for (final segment in path.split('.')) {
    if (node is! Map) return null;
    node = node[segment];
  }
  return node;
}

void _writePath(Map<String, dynamic> target, String path, Object? value) {
  final segments = path.split('.');
  if (segments.length == 1) {
    target[path] = value;
    return;
  }

  var node = target;
  for (final segment in segments.take(segments.length - 1)) {
    final next = node[segment];
    node = next is Map<String, dynamic>
        ? next
        : (node[segment] = <String, dynamic>{});
  }
  node[segments.last] = value;
}

/// Writable leaves reachable from [components] — the payload-side mirror of
/// `RuleExtractor::childrenOf()` on the Laravel side. A hidden or disabled
/// container gates its *entire* subtree before recursion, not only the
/// leaves inside it: Filament lets a form hide or disable a whole `Section`,
/// and every field inside inherits that rather than needing its own flag.
/// Checking only leaves (the original bug here) let a field nested under a
/// hidden or disabled container survive into the payload because its own
/// `hidden`/`disabled` defaulted to false.
///
/// `writable` gates the same way: `false` means the server cannot persist
/// this field at all (a limit of this package, not a UI decision), so
/// submitting it is a control whose contents are discarded behind a `200`.
///
/// Top-level and shared, not private to [FormValues]: `client_validator.dart`
/// needs the exact same set of fields — a rule on a field this walk would
/// exclude from the payload can only produce an error the user can neither
/// see nor fix. Task 7 shipped a Critical from this bug class once already;
/// two textually-parallel private copies of this descent are not a guarantee
/// that survives editing, so there is exactly one now.
Iterable<SchemaComponent> writableFields(
  List<SchemaComponent> components,
) sync* {
  for (final component in components) {
    if (component.hidden || component.disabled || !component.writable) {
      continue;
    }
    switch (component) {
      case LayoutComponent(:final children):
        yield* writableFields(children);
      case UnknownComponent(:final children):
        yield* writableFields(children);
      case FileComponent(:final readOnly) when readOnly:
        continue;
      // A repeater is one writable field, its own name — never its item
      // template's field names — the client-side mirror of `WritableNames`
      // contributing only the repeater's own key. A readOnly repeater (a
      // relationship, or an older server that never published config) has
      // the same nowhere-to-go problem a readOnly file field does.
      case RepeaterComponent(:final readOnly) when readOnly:
        continue;
      default:
        if (component.name != null) yield component;
    }
  }
}
