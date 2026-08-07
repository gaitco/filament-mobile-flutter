import '../ports/filament_strings.dart';
import '../schema/schema_component.dart';
import '../schema/validation_rules.dart';
import 'form_values.dart';

/// Client-side validation hints — feedback only, never the last word.
///
/// The `rules` block on each component is a hint for immediate feedback; the
/// server revalidates every submission and its `422` message is authoritative,
/// arriving already translated in the panel's locale. So a rule here may only
/// *delay* a submission a round-trip on an obvious typo — never forbid one
/// the server would accept.
///
/// Pure and synchronous — no I/O, no `BuildContext` — so it is testable
/// without a widget. Returns field name to message; empty when the form
/// passes its client-side hints.
Map<String, String> validate(
  List<SchemaComponent> components,
  FormValues values, [
  FilamentStrings strings = const FilamentStrings(),
]) {
  final errors = <String, String>{};
  for (final field in writableFields(components)) {
    final message = _validateField(field, values, strings);
    if (message != null) errors[field.name!] = message;

    if (field is RepeaterComponent) {
      errors.addAll(_validateRows(field, values, strings));
    }
  }
  return errors;
}

/// Per-row, per-child errors for a repeater — [_validateField] run against
/// each child's own rules exactly as it runs for a flat field, just fed a
/// [FormValues] seeded from one row instead of the whole form. Keyed
/// `'<repeater>.<row>.<child>'`, the same shape Laravel's own `422` uses for
/// `items.0.name`, so a required child empty in row 2 lands on row 2 — never
/// folded into one generic message for the whole repeater.
Map<String, String> _validateRows(
  RepeaterComponent field,
  FormValues values,
  FilamentStrings strings,
) {
  final rows = values[field.name!];
  if (rows is! List) return const {};

  final errors = <String, String>{};
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    if (row is! Map) continue;

    final rowValues = FormValues.initial(
      field.children,
      from: Map<String, dynamic>.from(row),
    );
    for (final child in writableFields(field.children)) {
      final message = _validateField(child, rowValues, strings);
      if (message != null) {
        errors['${field.name}.$index.${child.name}'] = message;
      }
    }
  }
  return errors;
}

String? _validateField(
  SchemaComponent field,
  FormValues values,
  FilamentStrings strings,
) {
  final rules = field.rules;
  final value = values[field.name!];

  // `false` and `0` are real answers, not absence of one — only null and a
  // blank/whitespace string count as empty. An empty *optional* field skips
  // every rule below it: nothing else may block a field the user may leave
  // alone.
  if (_isEmpty(value)) {
    return rules.required
        ? _message(rules, 'required', strings.fieldRequired)
        : null;
  }

  // Not a `rules`-driven check — SchemaWalker's `color` branch has nothing
  // to say about the VALUE, only the format string (see `contract/
  // README.md`'s "The color field") — so this reads [ColorComponent.format]
  // off the component itself, the same split `_measure`'s `rules.numeric`
  // keying draws below between what `rules` carries and what the node's own
  // shape decides. `ColorComponent.isValid` is the exact check
  // `ColorFieldWidget`'s swatch is driven from, so "malformed" cannot mean
  // two different things in two places.
  //
  // Fix round 1, Finding 3: gated on `values.dirty`, unlike every check
  // below it. Those mirror a rule the SERVER declared (`rules.email` etc.
  // only exists because RuleExtractor emitted it, so the server genuinely
  // rejects the value too) — this one does not, since Filament applies no
  // format validation to a bare ColorPicker. An unrestricted check here
  // would refuse to submit the WHOLE form over a legacy stored value
  // (`#aabbccdd`, `rgb(10 20 30)` — both valid CSS the four Filament-
  // documented regexes don't cover) that the user never touched, which is
  // exactly the class of bug this docblock's own "never forbid one the
  // server would accept" rule exists to prevent. Scoping to a value the
  // user actually edited keeps the malformed-blocks-submission property for
  // what it was meant for.
  if (field is ColorComponent &&
      value is String &&
      values.dirty.contains(field.name) &&
      !ColorComponent.isValid(value, field.format)) {
    return strings.fieldColor;
  }

  // Forward-looking: `SchemaWalker::rules()` (`SchemaWalker.php:340-361`)
  // never emits `email`, `url`, `regex` or `confirmed` today — none of them
  // appear in `contract/laravel-panel.json` — so these branches are dead
  // against the current server. `ValidationRules` has parsed them since an
  // earlier phase regardless, and they cost nothing while they never fire.
  // The server would need to start emitting the corresponding rule key
  // before any of the four could actually trip.
  if (rules.email && value is String && !_emailPattern.hasMatch(value)) {
    return _message(rules, 'email', strings.fieldEmail);
  }
  if (rules.url && value is String && !_isValidUrl(value)) {
    return _message(rules, 'url', strings.fieldUrl);
  }
  if (rules.regex != null &&
      value is String &&
      !_matchesPattern(rules.regex!, value)) {
    return _message(rules, 'regex', strings.fieldPattern);
  }

  final measured = _measure(rules, value);
  if (measured != null) {
    if (rules.min != null && measured < rules.min!) {
      return _message(rules, 'min', strings.fieldMin(rules.min!));
    }
    if (rules.max != null && measured > rules.max!) {
      return _message(rules, 'max', strings.fieldMax(rules.max!));
    }
  }

  if (rules.confirmed && value != values['${field.name}_confirmation']) {
    return _message(rules, 'confirmed', strings.fieldConfirmed);
  }

  return null;
}

/// Prefers the server's own translated message for [rule], published beside
/// it in `rules.messages`; falls back to the host's [FilamentStrings] entry
/// per rule (not per field) so a field whose `required` came with a message
/// but whose `max` did not still gets a sensible `max` message.
String _message(ValidationRules rules, String rule, String fallback) =>
    rules.messages[rule] ?? fallback;

bool _isEmpty(Object? value) => switch (value) {
  null => true,
  final String s => s.trim().isEmpty,
  _ => false, // a bool `false` or a numeric `0` is a real answer.
};

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool _isValidUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && uri.hasScheme && uri.host.isNotEmpty;
}

/// A pattern Dart cannot compile fails open rather than blocking the form —
/// the server revalidates regardless, so a hint that can't even parse is
/// worth nothing here.
bool _matchesPattern(String source, String value) {
  try {
    return RegExp(source).hasMatch(value);
  } on FormatException {
    return true;
  }
}

/// `min`/`max` mean a **value** on a number and a **length** on everything
/// else — which is not this package's invention but Laravel's, and the client
/// has to match it or it forbids submissions the server accepts.
///
/// Keyed off `rules.numeric`, published by `RuleExtractor` for exactly the
/// rule Laravel's own validator reads `min`/`max` as value bounds against —
/// **not** the node's `type`. `SchemaWalker::refineType()` checks `isEmail()`
/// and `isPassword()` before `isNumeric()`, so `->email()->numeric()` types as
/// `email` while still validating numerically; keying off the component type
/// would measure a length there and block what the server accepts. Verified
/// against the real validator rather than reasoned about: `numeric|min:3`
/// PASSES for `5`, `numeric|max:3` FAILS for `500`, while a bare `min:3` fails
/// for `'5'` and passes for `'500'`.
///
/// So the length reading is only correct for the non-numeric half. Applied to a
/// number it makes `->numeric()->minLength(3)` unsubmittable for every value
/// under 100 — a hint forbidding what the server would accept, which §7 of the
/// contract does not allow.
///
/// A number the client cannot parse measures nothing and blocks nothing: the
/// server owns that verdict.
num? _measure(ValidationRules rules, Object? value) => rules.numeric
    ? (value is num ? value : num.tryParse(value.toString()))
    : value?.toString().length;
