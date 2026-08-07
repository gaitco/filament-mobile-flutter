import 'dart:convert';

import 'package:filament_mobile/form/client_validator.dart';
import 'package:filament_mobile/form/form_values.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds fields by parsing contract JSON through the real parser, matching
/// the fixture style in `form_values_test.dart` — these exercise
/// [SchemaComponent.fromJson] rather than hand-built objects, which isn't
/// even possible from here since every subclass constructor is private to
/// the schema library.
SchemaComponent textField(
  String name, {
  bool required = false,
  bool hidden = false,
  bool disabled = false,
  int? min,
  int? max,
  bool email = false,
  String? regex,
  Map<String, String>? messages,
}) {
  return SchemaComponent.fromJson({
    'type': 'text',
    'name': name,
    if (hidden) 'hidden': true,
    if (disabled) 'disabled': true,
    'rules': {
      if (required) 'required': true,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (email) 'email': true,
      if (regex != null) 'regex': regex,
      if (messages != null) 'messages': messages,
    },
  }, 'test');
}

/// An `email`-typed field — still a [TextComponent] under the hood (see
/// `SchemaComponent.fromJson`'s `'email' => TextComponent`), which is exactly
/// what lets `->email()->numeric()` type as `email` while validating
/// numerically.
SchemaComponent emailField(
  String name, {
  int? min,
  int? max,
  bool numeric = false,
}) {
  return SchemaComponent.fromJson({
    'type': 'email',
    'name': name,
    'rules': {
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (numeric) 'numeric': true,
    },
  }, 'test');
}

SchemaComponent colorField(
  String name, {
  String format = 'hex',
  bool required = false,
}) {
  return SchemaComponent.fromJson({
    'type': 'color',
    'name': name,
    'config': {'format': format},
    'rules': {if (required) 'required': true},
  }, 'test');
}

SchemaComponent toggleField(String name, {bool required = false}) {
  return SchemaComponent.fromJson({
    'type': 'toggle',
    'name': name,
    'rules': {if (required) 'required': true},
  }, 'test');
}

// `numeric` defaults true: a real `number`-typed component always carries it
// — `RuleExtractor` emits `numeric` from the same `isNumeric()` check that
// drives the walker's type refinement to `number` in the first place — so a
// bare `numberField(...)` here matches what the server actually sends.
SchemaComponent numberField(
  String name, {
  bool required = false,
  int? min,
  int? max,
  bool numeric = true,
}) {
  return SchemaComponent.fromJson({
    'type': 'number',
    'name': name,
    'rules': {
      if (required) 'required': true,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (numeric) 'numeric': true,
    },
  }, 'test');
}

/// Re-derives raw JSON for a component this file already built, including
/// its `rules`, so [section]'s children round-trip through the real parser
/// rather than being attached by hand. Recurses for a container child so
/// two-level nesting round-trips too — see `form_values_test.dart`'s
/// `_rawJson`, which this mirrors.
Map<String, dynamic> _rawJson(SchemaComponent child) {
  return {
    'type': child.type,
    if (child.name != null) 'name': child.name,
    if (child.hidden) 'hidden': true,
    if (child.disabled) 'disabled': true,
    'rules': {
      if (child.rules.required) 'required': true,
      if (child.rules.min != null) 'min': child.rules.min,
      if (child.rules.max != null) 'max': child.rules.max,
      if (child.rules.email) 'email': true,
      if (child.rules.url) 'url': true,
      if (child.rules.regex != null) 'regex': child.rules.regex,
      if (child.rules.confirmed) 'confirmed': true,
    },
    if (child is LayoutComponent)
      'children': child.children.map(_rawJson).toList(),
    if (child is UnknownComponent)
      'children': child.children.map(_rawJson).toList(),
  };
}

SchemaComponent section(
  List<SchemaComponent> children, {
  bool hidden = false,
  bool disabled = false,
}) {
  return SchemaComponent.fromJson({
    'type': 'section',
    if (hidden) 'hidden': true,
    if (disabled) 'disabled': true,
    'children': children.map(_rawJson).toList(),
  }, 'test');
}

void main() {
  final strings = const FilamentStrings();

  test('required rejects null, empty and whitespace', () {
    final components = [textField('name', required: true)];

    for (final value in [null, '', '   ']) {
      final values = FormValues.initial(components).set('name', value);
      expect(
        validate(components, values, strings),
        contains('name'),
        reason: 'a value of ${jsonEncode(value)} must fail required',
      );
    }
  });

  test('required accepts false, which is a real boolean answer', () {
    // The bug this catches: treating `false` as empty, so a required toggle
    // can only be submitted when it is ON.
    final components = [toggleField('active', required: true)];
    final values = FormValues.initial(components).set('active', false);

    expect(validate(components, values, strings), isEmpty);
  });

  test('required accepts zero', () {
    final components = [numberField('qty', required: true)];
    final values = FormValues.initial(components).set('qty', 0);

    expect(validate(components, values, strings), isEmpty);
  });

  test('min and max measure a length on a text field', () {
    final tooLong = [textField('name', max: 3)];
    expect(
      validate(tooLong, FormValues.initial(tooLong).set('name', 'abcd')),
      contains('name'),
    );

    final tooShort = [textField('name', min: 3)];
    expect(
      validate(tooShort, FormValues.initial(tooShort).set('name', 'ab')),
      contains('name'),
    );

    final ok = [textField('name', min: 3, max: 3)];
    expect(validate(ok, FormValues.initial(ok).set('name', 'abc')), isEmpty);
  });

  test('min and max measure a VALUE on a number field', () {
    // Pins Laravel's own semantics, checked against the real validator:
    // `RuleExtractor` emits `numeric` beside `min:`/`max:` for exactly the
    // field the walker types as `number`, and `numeric|max:3` FAILS for 500
    // while `numeric|min:3` PASSES for 5.
    final overMax = [numberField('qty', max: 3)];
    expect(
      validate(overMax, FormValues.initial(overMax).set('qty', 500)),
      contains('qty'),
      reason: 'the server rejects 500 under numeric|max:3',
    );

    final underMax = [numberField('qty', max: 3)];
    expect(
      validate(underMax, FormValues.initial(underMax).set('qty', 2)),
      isEmpty,
    );
  });

  test(
    'a small number is submittable under a min the server reads as a value',
    () {
      // The defect this replaces: measuring digits made 5 fail `min: 3` on a
      // `->numeric()->minLength(3)` field, i.e. the client forbade a submission
      // the server accepts. A hint may only ever delay one.
      final number = [numberField('qty', min: 3)];

      for (final value in [5, '5', 3]) {
        expect(
          validate(number, FormValues.initial(number).set('qty', value)),
          isEmpty,
          reason: '$value passes numeric|min:3 on the server',
        );
      }

      expect(
        validate(number, FormValues.initial(number).set('qty', 2)),
        contains('qty'),
        reason: '2 genuinely fails numeric|min:3',
      );
    },
  );

  test('a number the client cannot parse blocks nothing', () {
    // The server owns that verdict — it holds the `numeric` rule itself.
    // `min: 5`, not 3: under the length reading `'abc'` measures 3 and passes
    // a min of 3 anyway, so the test would stay green for the wrong reason.
    final number = [numberField('qty', min: 5)];

    expect(
      validate(number, FormValues.initial(number).set('qty', 'abc')),
      isEmpty,
    );
  });

  test('a numeric field compares values, not lengths', () {
    // The bug this closes: `->numeric()->minLength(3)` publishes min: 3, and a
    // length comparison rejects 5 — a submission Laravel accepts, since
    // `numeric|min:3` is a VALUE bound. A client hint must never forbid what
    // the server would take.
    final components = [numberField('qty', min: 3, numeric: true)];
    final values = FormValues.initial(components).set('qty', 5);

    expect(validate(components, values, strings), isEmpty);
  });

  test('an email field carrying numeric still compares values', () {
    // ->email()->numeric() types as `email`, so a client keying off the
    // component type measures a length here and blocks. Keying off the rule
    // is the whole point of Task 5.
    final components = [emailField('code', min: 3, numeric: true)];
    final values = FormValues.initial(components).set('code', '5');

    expect(validate(components, values, strings), isEmpty);
  });

  test('a non-numeric field still compares lengths', () {
    final components = [textField('name', min: 3)];
    final values = FormValues.initial(components).set('name', 'ab');

    expect(validate(components, values, strings), contains('name'));
  });

  test('an empty optional field skips every other rule', () {
    // A blank optional email is valid. Running the email rule on it would
    // block a form for a field the user is allowed to leave alone.
    final components = [textField('email', email: true)];
    final values = FormValues.initial(components).set('email', '');

    expect(validate(components, values, strings), isEmpty);
  });

  test('a hidden or disabled field is never validated', () {
    // It is not in the payload, so a rule on it can only produce an error the
    // user cannot see or fix — a form that cannot be submitted and does not
    // say why.
    final components = [textField('secret', required: true, hidden: true)];

    expect(
      validate(components, FormValues.initial(components), strings),
      isEmpty,
    );
  });

  test('an invalid regex fails open rather than blocking the form', () {
    // A server-supplied pattern that Dart cannot compile must not make the
    // form unsubmittable. The server revalidates regardless.
    final components = [textField('code', regex: '([')];
    final values = FormValues.initial(components).set('code', 'anything');

    expect(validate(components, values, strings), isEmpty);
  });

  test('messages come from the host strings', () {
    const arabic = FilamentStrings(fieldRequired: 'هذا الحقل مطلوب');
    final components = [textField('name', required: true)];

    expect(
      validate(components, FormValues.initial(components), arabic)['name'],
      'هذا الحقل مطلوب',
    );
  });

  test('prefers the server message over the local string', () {
    const local = FilamentStrings(fieldRequired: 'LOCAL');
    final components = [
      textField(
        'name',
        required: true,
        messages: {'required': 'هذا الحقل مطلوب'},
      ),
    ];

    expect(
      validate(components, FormValues.initial(components), local)['name'],
      'هذا الحقل مطلوب',
    );
  });

  test('falls back to the local string when a rule has no server message', () {
    // A server that does not send `messages` must keep working.
    const local = FilamentStrings(fieldRequired: 'LOCAL');
    final components = [textField('name', required: true)];

    expect(
      validate(components, FormValues.initial(components), local)['name'],
      'LOCAL',
    );
  });

  test('falls back per rule, not per field', () {
    // A field whose `required` has a message but whose `max` does not must
    // still produce the local max message, rather than an empty string.
    const local = FilamentStrings();
    final components = [
      textField('name', required: true, max: 3, messages: {'required': 'AR'}),
    ];
    final values = FormValues.initial(components).set('name', 'abcd');

    expect(validate(components, values, local)['name'], local.fieldMax(3));
  });

  group('color', () {
    test('a value matching its declared format passes', () {
      final hex = [colorField('brand')];
      expect(
        validate(hex, FormValues.initial(hex).set('brand', '#336699')),
        isEmpty,
      );

      final rgba = [colorField('brand', format: 'rgba')];
      expect(
        validate(
          rgba,
          FormValues.initial(rgba).set('brand', 'rgba(1, 2, 3, 0.5)'),
        ),
        isEmpty,
      );
    });

    test('a malformed value blocks with the color message, not a bare '
        'error flag', () {
      final hex = [colorField('brand')];
      final errors = validate(
        hex,
        FormValues.initial(hex).set('brand', 'not a color'),
        strings,
      );

      expect(errors, contains('brand'));
      expect(errors['brand'], strings.fieldColor);
    });

    test('a value valid in another format is rejected — no cross-format '
        'leniency', () {
      // The mirror of the "never converts" property: a value that IS a real
      // colour, just not in the DECLARED format, must still be treated as
      // malformed. Accepting it here would be the validator quietly doing
      // the conversion `ColorFieldWidget` explicitly never does.
      final rgb = [colorField('brand', format: 'rgb')];
      final errors = validate(
        rgb,
        FormValues.initial(rgb).set('brand', '#336699'),
      );

      expect(errors, contains('brand'));
    });

    test('fix round 1, Finding 3: an untouched malformed value is not '
        'blocked — only what the user actually edited', () {
      // Filament applies no server-side format validation to a bare
      // ColorPicker, so a value already stored outside the four regexes
      // (a legacy record, or CSS the docs regex doesn't cover — see the
      // two examples below) is not something the server would reject
      // either. Blocking it unconditionally would refuse the whole form
      // over a field the user never touched.
      final hex = [colorField('brand')];
      final fromRecord = FormValues.initial(
        hex,
        from: const {'brand': '#aabbccdd'}, // 8-digit hex+alpha: valid CSS
      );

      expect(validate(hex, fromRecord, strings), isEmpty);

      final rgb = [colorField('brand', format: 'rgb')];
      final spaceSyntax = FormValues.initial(
        rgb,
        from: const {'brand': 'rgb(10 20 30)'}, // CSS space syntax
      );

      expect(validate(rgb, spaceSyntax, strings), isEmpty);
    });

    test('once the user edits it, the same malformed value blocks — dirty '
        'is the gate, not a free pass', () {
      final hex = [colorField('brand')];
      // set() marks dirty even when re-writing the same value — the field
      // is genuinely edited here, unlike the untouched case above.
      final edited = FormValues.initial(
        hex,
        from: const {'brand': '#aabbccdd'},
      ).set('brand', '#aabbccdd');

      expect(validate(hex, edited, strings), contains('brand'));
    });

    test('an empty, non-required color field is not blocked', () {
      final hex = [colorField('brand')];
      expect(
        validate(hex, FormValues.initial(hex).set('brand', null)),
        isEmpty,
      );
    });

    test('required still wins over the format check on an empty value', () {
      final hex = [colorField('brand', required: true)];
      final errors = validate(
        hex,
        FormValues.initial(hex).set('brand', ''),
        strings,
      );

      expect(errors['brand'], strings.fieldRequired);
    });

    test('an rgb value is never accepted as its hex equivalent — the '
        'never-converts property', () {
      // Proves the claim by attempted violation: if the validator (or
      // anything upstream) silently converted a declared `rgb` value into
      // hex before checking it, this hex string would pass an `rgb` field.
      // It must not.
      final rgb = [colorField('brand', format: 'rgb')];
      final errors = validate(
        rgb,
        // The hex equivalent of rgb(51, 102, 153).
        FormValues.initial(rgb).set('brand', '#336699'),
      );

      expect(
        errors,
        contains('brand'),
        reason: 'a hex string must not be accepted on a field declared rgb',
      );
    });
  });

  group('nested containers — must agree with FormValues.payloadFor', () {
    // Task 7's Critical: a hidden or disabled *container* gates every field
    // inside it, not just fields with their own flag set. The validator has
    // to skip the same fields `payloadFor` omits from the payload — a rule
    // on a field that will never be submitted can only be a stuck, unfixable
    // error.

    test('a required field nested in a plain container is still validated', () {
      // Positive control: proves the container recursion itself works, so
      // the next two tests are demonstrating the hidden/disabled gate and
      // not a walker that skips every container's contents.
      final components = [
        section([textField('secret', required: true)]),
      ];

      expect(
        validate(components, FormValues.initial(components), strings),
        contains('secret'),
      );
    });

    test('a required field inside a hidden container is never validated', () {
      final components = [
        section([textField('secret', required: true)], hidden: true),
      ];

      expect(
        validate(components, FormValues.initial(components), strings),
        isEmpty,
      );
    });

    test('a required field inside a disabled container is never validated', () {
      final components = [
        section([textField('secret', required: true)], disabled: true),
      ];

      expect(
        validate(components, FormValues.initial(components), strings),
        isEmpty,
      );
    });

    test(
      'a required field two containers deep is gated by either ancestor',
      () {
        final components = [
          section([
            section([textField('secret', required: true)], hidden: true),
          ]),
        ];

        expect(
          validate(components, FormValues.initial(components), strings),
          isEmpty,
        );
      },
    );
  });
}
