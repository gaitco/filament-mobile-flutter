import 'dart:convert';

import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/contract_goldens.dart';

/// Every `type` string a **form** node (never `infolist` — those are entry
/// types this registry deliberately never renders) carries in the committed
/// golden [file], excluding the four layout types — `renderableTypes` covers
/// leaf field types, and a layout container is walked for its children, not
/// asked for a widget of its own. The same file `contract_test.dart`'s
/// `fixture()` reads, from the same relative path.
///
/// Entry types are excluded too: since P10 a `Placeholder` legitimately
/// arrives as a `text_entry` node inside a **form**, and an entry in a form
/// renders nothing on purpose (read-only, no value to write) — the registry's
/// `_ => SizedBox.shrink()` arm, not a missing widget.
Set<String> _writableTypesIn(String file) {
  final panel =
      jsonDecode(contractFile(file).readAsStringSync()) as Map<String, dynamic>;
  const layoutTypes = {'section', 'grid', 'tabs', 'fieldset'};
  const entryTypes = {
    'text_entry',
    'badge_entry',
    'image_entry',
    'boolean_entry',
    'date_entry',
    'rich_entry',
  };
  final types = <String>{};

  void walk(List<dynamic> nodes) {
    for (final raw in nodes) {
      final node = raw as Map<String, dynamic>;
      final type = node['type'] as String;
      if (!layoutTypes.contains(type) && !entryTypes.contains(type)) {
        types.add(type);
      }
      final children = node['children'] as List<dynamic>?;
      if (children != null) walk(children);
    }
  }

  for (final raw in panel['resources'] as List<dynamic>) {
    walk((raw as Map<String, dynamic>)['form'] as List<dynamic>);
  }

  return types;
}

SchemaComponent fieldOfType(String type, {required String name}) =>
    SchemaComponent.fromJson({
      'type': type,
      'name': name,
      'label': name,
    }, 'form[0]');

SchemaComponent selectField(
  String name, {
  required Map<Object, String> options,
  String type = 'select',
}) => SchemaComponent.fromJson({
  'type': type,
  'name': name,
  'label': name,
  'config': {
    'options': [
      for (final entry in options.entries)
        {'value': entry.key, 'label': entry.value},
    ],
  },
}, 'form[0]');

SchemaComponent fileField(String name) => SchemaComponent.fromJson({
  'type': 'file',
  'name': name,
  'label': name,
}, 'form[0]');

Widget harness({
  FieldRegistry? registry,
  required SchemaComponent component,
  required FieldState state,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => (registry ?? FieldRegistry.defaults()).build(
          context,
          component,
          state,
        ),
      ),
    ),
  );
}

void main() {
  // One test per type, each asserting the same four properties: it renders,
  // it reports changes, it shows an error, and it honours enabled: false.
  // A field that renders but silently swallows onChanged is the failure this
  // catches — and it is invisible to a "renders without throwing" test.
  for (final type in [
    'text',
    'textarea',
    'email',
    'password',
    'number',
    'color',
  ]) {
    testWidgets('$type reports what the user types', (tester) async {
      Object? received;
      await tester.pumpWidget(
        harness(
          component: fieldOfType(type, name: 'f'),
          state: FieldState(value: null, onChanged: (v) => received = v),
        ),
      );

      await tester.enterText(find.byType(TextField), '42');
      expect(received, isNotNull, reason: '$type must report changes');
    });
  }

  testWidgets('a select reports the chosen option value, not its label', (
    tester,
  ) async {
    // The contract allows int values (foreign keys) with string labels;
    // sending the label back is the classic bug here.
    Object? received;
    await tester.pumpWidget(
      harness(
        component: selectField('company_id', options: {3: 'Acme'}),
        state: FieldState(value: null, onChanged: (v) => received = v),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<Object?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme').last);
    await tester.pumpAndSettle();

    expect(received, 3);
  });

  testWidgets('a disabled field reports nothing', (tester) async {
    // enabled: false must make the control inert, not merely grey. A field
    // that looks disabled and still fires onChanged is how a refused value
    // reaches a payload.
    Object? received;
    await tester.pumpWidget(
      harness(
        component: fieldOfType('text', name: 'f'),
        state: FieldState(
          value: 'x',
          onChanged: (v) => received = v,
          enabled: false,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'crafted');
    expect(received, isNull);
  });

  testWidgets('a file field always renders disabled', (tester) async {
    Object? received;
    await tester.pumpWidget(
      harness(
        component: fileField('avatar'),
        state: FieldState(value: 'a.jpg', onChanged: (v) => received = v),
      ),
    );

    await tester.enterText(find.byType(TextField), 'b.jpg');
    expect(received, isNull);
  });

  // The "text" and "file" cases above only exercise 2 of the 12 writable
  // types for inertness. Flutter's TextField happens to force `readOnly`
  // internally whenever `enabled` is false (a second, framework-level guard
  // independent of `onChanged`), so a disabled TextField is protected even
  // if the wiring here regressed — but DropdownButtonFormField, Switch,
  // Checkbox and the date TextField's onTap have no such built-in second
  // guard. Each of the remaining ten types gets its own attack here, driving
  // the exact gesture that type accepts, so a regression in the one gating
  // line has somewhere to turn red.
  for (final type in ['textarea', 'email', 'password', 'color']) {
    testWidgets('$type disabled reports nothing', (tester) async {
      Object? received;
      await tester.pumpWidget(
        harness(
          component: fieldOfType(type, name: 'f'),
          state: FieldState(
            value: 'x',
            onChanged: (v) => received = v,
            enabled: false,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'crafted');
      expect(received, isNull);
    });
  }

  testWidgets('number disabled reports nothing', (tester) async {
    Object? received;
    await tester.pumpWidget(
      harness(
        component: fieldOfType('number', name: 'f'),
        state: FieldState(
          value: 1,
          onChanged: (v) => received = v,
          enabled: false,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '42');
    expect(received, isNull);
  });

  testWidgets('select disabled does not open its menu or report anything', (
    tester,
  ) async {
    Object? received;
    await tester.pumpWidget(
      harness(
        component: selectField('company_id', options: {3: 'Acme'}),
        state: FieldState(
          value: null,
          onChanged: (v) => received = v,
          enabled: false,
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<Object?>));
    await tester.pumpAndSettle();

    // The real attack: does the menu even open? Nothing selected either way,
    // so `received` staying null is necessary but not sufficient — a menu
    // that opened and simply wasn't tapped would pass that half alone.
    expect(find.text('Acme'), findsNothing);
    expect(received, isNull);
  });

  testWidgets('multiselect disabled reports nothing', (tester) async {
    Object? received;
    await tester.pumpWidget(
      harness(
        component: selectField(
          'tags',
          options: {1: 'One'},
          type: 'multiselect',
        ),
        state: FieldState(
          value: const <Object>[],
          onChanged: (v) => received = v,
          enabled: false,
        ),
      ),
    );

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    expect(received, isNull);
  });

  testWidgets('a multiselect reports option values, not labels', (
    tester,
  ) async {
    // Pinned separately from the single-select case: SelectComponent covers
    // both `select` and `multiselect` through the same class, and only the
    // single-select path was covered before.
    Object? received;
    await tester.pumpWidget(
      harness(
        component: selectField(
          'tags',
          options: {1: 'One', 2: 'Two'},
          type: 'multiselect',
        ),
        state: FieldState(
          value: const <Object>[],
          onChanged: (v) => received = v,
        ),
      ),
    );

    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();

    expect(received, [1]);
  });

  testWidgets('toggle disabled reports nothing', (tester) async {
    Object? received;
    await tester.pumpWidget(
      harness(
        component: fieldOfType('toggle', name: 'f'),
        state: FieldState(
          value: false,
          onChanged: (v) => received = v,
          enabled: false,
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(received, isNull);
  });

  testWidgets('checkbox disabled reports nothing', (tester) async {
    Object? received;
    await tester.pumpWidget(
      harness(
        component: fieldOfType('checkbox', name: 'f'),
        state: FieldState(
          value: false,
          onChanged: (v) => received = v,
          enabled: false,
        ),
      ),
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(received, isNull);
  });

  for (final type in ['date', 'datetime']) {
    testWidgets('$type disabled does not open its picker or report anything', (
      tester,
    ) async {
      Object? received;
      await tester.pumpWidget(
        harness(
          component: fieldOfType(type, name: 'f'),
          state: FieldState(
            value: null,
            onChanged: (v) => received = v,
            enabled: false,
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsNothing);
      expect(received, isNull);
    });
  }

  testWidgets('an error message is shown', (tester) async {
    await tester.pumpWidget(
      harness(
        component: fieldOfType('text', name: 'f'),
        state: FieldState(
          value: null,
          onChanged: (_) {},
          error: 'حقل الاسم مطلوب',
        ),
      ),
    );

    expect(find.text('حقل الاسم مطلوب'), findsOneWidget);
  });

  testWidgets('a host override wins over the built-in', (tester) async {
    final registry = FieldRegistry.defaults()
      ..register('text', (context, component, state) => const Text('mine'));

    await tester.pumpWidget(
      harness(
        registry: registry,
        component: fieldOfType('text', name: 'f'),
        state: FieldState(value: null, onChanged: (_) {}),
      ),
    );

    expect(find.text('mine'), findsOneWidget);
  });

  test(
    'renderableTypes covers every writable type the real golden panel emits',
    () {
      // Fix round 1, Finding 4: this used to be a hand-typed `containsAll`
      // subset carrying the comment "Derived, not restated" while being
      // exactly the hand-maintained list that comment claimed not to be —
      // and `time` silently rotted out of it for the two commits between
      // Task 2 shipping it and this fix round noticing. `_writableTypesIn`
      // reads the same committed golden `laravel_contract_test.dart` already
      // treats as ground truth, so a type the wire actually emits with no
      // widget fails HERE, on the type itself, not on a copy of it someone
      // remembered to update.
      final golden = _writableTypesIn('laravel-panel.json');
      expect(golden, isNotEmpty);
      expect(FieldRegistry.defaults().renderableTypes, containsAll(golden));
    },
  );

  testWidgets('a select whose value is not among its options still renders', (
    tester,
  ) async {
    // Found by the write pilot: DropdownButtonFormField *asserts* when its
    // value matches no item, and the assertion takes the whole form down with
    // a red screen. A dependent picker (`company_id` narrowed by the chosen
    // `user_id`) shrinks its options on every `/state` response, so a value
    // outside the list is the normal course of events, not a corner case.
    await tester.pumpWidget(
      harness(
        component: selectField('company_id', options: {1: 'One', 2: 'Two'}),
        state: const FieldState(value: 99, onChanged: _ignore),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(DropdownButtonFormField<Object?>), findsOneWidget);
    // Nothing is shown as chosen — the option is gone, so the field is empty.
    expect(find.text('One'), findsNothing);
    expect(find.text('Two'), findsNothing);
  });
}

void _ignore(Object? value) {}
