import 'package:filament_mobile/form/form_values.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a text field by parsing contract JSON through the real parser, so
/// these fixtures exercise [SchemaComponent.fromJson] rather than hand-built
/// objects (which isn't even possible from here — every subclass constructor
/// is private to the schema library).
SchemaComponent textField(
  String name, {
  bool hidden = false,
  bool disabled = false,
  bool writable = true,
}) {
  return SchemaComponent.fromJson({
    'type': 'text',
    'name': name,
    if (hidden) 'hidden': true,
    if (disabled) 'disabled': true,
    if (!writable) 'writable': false,
  }, 'test');
}

SchemaComponent selectField(String name, {required Object? defaultValue}) {
  return SchemaComponent.fromJson({
    'type': 'select',
    'name': name,
    'default': defaultValue,
  }, 'test');
}

SchemaComponent fileField(String name) {
  return SchemaComponent.fromJson({'type': 'file', 'name': name}, 'test');
}

/// A leaf with no `name` at all — the contract allows it (a component that
/// carries no key), and the walk must skip it rather than crash on a null
/// map key.
SchemaComponent unnamedField() {
  return SchemaComponent.fromJson({'type': 'text'}, 'test');
}

/// Re-derives raw JSON for a component this file already built, purely from
/// its public properties (there is no `toJson` on the schema — nor does one
/// exist to round-trip), so [section]'s children are parsed fresh rather than
/// attached by hand. Recurses for a container child so two-level nesting
/// round-trips too.
Map<String, dynamic> _rawJson(SchemaComponent child) {
  return {
    'type': child.type,
    if (child.name != null) 'name': child.name,
    if (child.hidden) 'hidden': true,
    if (child.disabled) 'disabled': true,
    if (!child.writable) 'writable': false,
    if (child is SelectComponent) 'default': child.defaultValue,
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

/// A container type this build doesn't recognise (Filament ships `wizard`,
/// `split`, etc.) — [UnknownComponent] still carries `children`, so a field
/// nested inside one must stay reachable.
SchemaComponent unknownContainer(
  List<SchemaComponent> children, {
  bool hidden = false,
  bool disabled = false,
}) {
  return SchemaComponent.fromJson({
    'type': 'wizard',
    if (hidden) 'hidden': true,
    if (disabled) 'disabled': true,
    'children': children.map(_rawJson).toList(),
  }, 'test');
}

void main() {
  group('payload', () {
    test('is built from the schema, not from the value map', () {
      // The client-side mirror of RuleExtractor's "no rule, no validated key,
      // no write". A key the schema does not declare can never reach the
      // server — so a stale value left behind by a /state swap, or anything a
      // host wrote into the map, is structurally unable to be submitted.
      final components = [textField('name'), textField('email')];
      var values = FormValues.initial(components);
      values = values.set('name', 'Sara').set('smuggled', 'nope');

      expect(values.payloadFor(components).keys, ['name', 'email']);
    });

    test('descends into layout containers', () {
      final components = [
        section([textField('name'), textField('email')]),
      ];
      final values = FormValues.initial(components).set('name', 'Sara');

      expect(
        values.payloadFor(components).keys,
        containsAll(['name', 'email']),
      );
    });

    test('omits a field the schema marks disabled', () {
      // The server refuses these anyway; sending them invites a 422 for a
      // field the user was never shown as editable.
      final components = [
        textField('name'),
        textField('locked', disabled: true),
      ];
      final values = FormValues.initial(components).set('locked', 'crafted');

      expect(values.payloadFor(components).containsKey('locked'), isFalse);
    });

    test('a non-writable field is excluded from the payload', () {
      // The client-side mirror of the server's own rule: a field the server
      // cannot persist must not be submitted, or the user fills a control
      // whose contents are discarded behind a 200.
      final components = [
        textField('name'),
        textField('locked', writable: false),
      ];
      final values = FormValues.initial(components).set('locked', 'typed');

      expect(values.payloadFor(components).containsKey('locked'), isFalse);
    });

    test('omits a hidden field', () {
      final components = [textField('name'), textField('secret', hidden: true)];
      final values = FormValues.initial(components).set('secret', 'x');

      expect(values.payloadFor(components).containsKey('secret'), isFalse);
    });

    test('omits a file field, which the server never writes', () {
      final components = [textField('name'), fileField('avatar')];
      final values = FormValues.initial(
        components,
      ).set('avatar', 'attacker.jpg');

      expect(values.payloadFor(components).containsKey('avatar'), isFalse);
    });

    test('omits every field nested inside a hidden container', () {
      // The container's own flag has to gate the whole subtree before
      // recursion — same as RuleExtractor::childrenOf() on the server —
      // because the individually-enabled child's own hidden/disabled default
      // to false and can't tell it was hidden by its parent.
      final components = [
        section([textField('secret')], hidden: true),
      ];
      final values = FormValues.initial(components).set('secret', 'leaked');

      expect(values.payloadFor(components).containsKey('secret'), isFalse);
    });

    test('omits every field nested inside a disabled container', () {
      final components = [
        section([textField('secret')], disabled: true),
      ];
      final values = FormValues.initial(components).set('secret', 'leaked');

      expect(values.payloadFor(components).containsKey('secret'), isFalse);
    });

    test(
      'gates a field two containers deep, not just the immediate parent',
      () {
        final components = [
          section([
            section([textField('secret')], hidden: true),
          ]),
        ];
        final values = FormValues.initial(components).set('secret', 'leaked');

        expect(values.payloadFor(components).containsKey('secret'), isFalse);
      },
    );

    test('omits a field nested inside a hidden unrecognised container', () {
      final components = [
        unknownContainer([textField('secret')], hidden: true),
      ];
      final values = FormValues.initial(components).set('secret', 'leaked');

      expect(values.payloadFor(components).containsKey('secret'), isFalse);
    });

    test('descends into an unrecognised container the same as a known one', () {
      final components = [
        unknownContainer([textField('email')]),
      ];
      final values = FormValues.initial(components).set('email', 'a@b.com');

      expect(values.payloadFor(components)['email'], 'a@b.com');
    });

    test(
      'a name repeated at two depths shares one slot, last write standing — '
      'the same collapsing RuleExtractor gets from building one rules map',
      () {
        final components = [
          textField('email'),
          section([textField('email')]),
        ];
        final values = FormValues.initial(components).set('email', 'a@b.com');

        expect(values.payloadFor(components)['email'], 'a@b.com');
        expect(values.payloadFor(components).keys.toSet(), {'email'});
      },
    );

    test('skips a leaf with no name rather than crashing', () {
      final components = [textField('name'), unnamedField()];
      final values = FormValues.initial(components);

      expect(values.payloadFor(components).keys, ['name']);
    });
  });

  group('initial values', () {
    test('seeds from each component default on create', () {
      final components = [selectField('status', defaultValue: 'draft')];
      expect(FormValues.initial(components)['status'], 'draft');
    });

    test('a record value wins over a default on edit', () {
      final components = [selectField('status', defaultValue: 'draft')];
      final values = FormValues.initial(components, from: {'status': 'live'});

      expect(values['status'], 'live');
    });

    test('an explicit null in the record beats a default', () {
      // A cleared field is a value. Falling back to the default here would
      // silently re-fill something the user deliberately emptied.
      final components = [selectField('status', defaultValue: 'draft')];
      final values = FormValues.initial(components, from: {'status': null});

      expect(values['status'], isNull);
    });
  });

  group('dirty', () {
    test('tracks only what changed', () {
      final components = [textField('name'), textField('email')];
      final values = FormValues.initial(components).set('name', 'Sara');

      expect(values.dirty, {'name'});
    });

    test('setting a value back to its initial still counts as dirty', () {
      // Simpler and safer than value comparison: an over-eager dirty set costs
      // one redundant field in a payload, an under-eager one loses an edit.
      final components = [textField('name')];
      final values = FormValues.initial(
        components,
        from: {'name': 'Sara'},
      ).set('name', 'Other').set('name', 'Sara');

      expect(values.dirty, {'name'});
    });
  });

  // The write pilot's headline blocker. A translatable Filament field is
  // published as `title.ar`, and Laravel validates that as `title[ar]` — so a
  // flat `{"title.ar": …}` reads as absent and every translatable resource
  // came back 422 "required" on fields the user had just filled.
  group('dotted names are paths, not literal keys', () {
    test('the payload nests a dotted field name', () {
      final components = [textField('title.ar'), textField('title.en')];
      final values = FormValues.initial(
        components,
      ).set('title.ar', 'مرحبا').set('title.en', 'Hello');

      expect(values.payloadFor(components), {
        'title': {'ar': 'مرحبا', 'en': 'Hello'},
      });
    });

    test('an undotted name stays flat beside a dotted one', () {
      final components = [textField('title.ar'), textField('slug')];
      final values = FormValues.initial(
        components,
      ).set('title.ar', 'مرحبا').set('slug', 'hello');

      expect(values.payloadFor(components), {
        'title': {'ar': 'مرحبا'},
        'slug': 'hello',
      });
    });

    test('a record seeds a dotted field through the same path', () {
      // GET /{resource}/{id} answers with the nesting `data_set` produced, so
      // reading `title.ar` as a literal key left every edit form blank — and
      // saving that blank form wrote the blanks back.
      final components = [textField('title.ar'), textField('title.en')];
      final values = FormValues.initial(
        components,
        from: {
          'title': {'ar': 'مرحبا', 'en': 'Hello'},
        },
      );

      expect(values['title.ar'], 'مرحبا');
      expect(values['title.en'], 'Hello');
    });

    test('an explicit null in the record still wins over the default', () {
      final components = [selectField('meta.kind', defaultValue: 'fallback')];
      final values = FormValues.initial(
        components,
        from: {
          'meta': {'kind': null},
        },
      );

      expect(values['meta.kind'], isNull);
    });

    test('a flat dotted key in the record is still read', () {
      // Defensive: a host or an older server sending the literal key must not
      // silently lose the value.
      final components = [textField('title.ar')];
      final values = FormValues.initial(
        components,
        from: {'title.ar': 'مرحبا'},
      );

      expect(values['title.ar'], 'مرحبا');
    });
  });
}
