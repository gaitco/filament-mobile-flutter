import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/form/fields/field_widgets.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsed through the real [SchemaComponent.fromJson], the same discipline
/// every fixture in this suite follows — a hand-built [KeyValueComponent]
/// could drift from what the wire (and the Laravel side's `keyvalueNode()`
/// fixture) actually produces.
SchemaComponent keyvalueField(
  String name, {
  bool addable = true,
  bool deletable = true,
  bool editableKeys = true,
  bool editableValues = true,
  String? keyLabel,
  String? valueLabel,
}) => SchemaComponent.fromJson({
  'type': 'keyvalue',
  'name': name,
  'label': name,
  'config': {
    'addable': addable,
    'deletable': deletable,
    'editableKeys': editableKeys,
    'editableValues': editableValues,
    'keyLabel': keyLabel,
    'valueLabel': valueLabel,
    'keyPlaceholder': null,
    'valuePlaceholder': null,
  },
}, 'form[0]');

/// A `StatefulBuilder` wrapper, like `tagsHarness`/`repeaterHarness` before
/// it: a non-rebuilding harness could report the right value on an edit
/// without ever proving the OTHER pairs survived, which is the whole point
/// of the "leaves pair 1 untouched" test below.
Widget keyvalueHarness({
  required SchemaComponent component,
  Object? value,
  bool enabled = true,
  String? error,
  ValueChanged<Object?>? onChanged,
}) {
  var current = value;
  return MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => FieldRegistry.defaults().build(
          context,
          component,
          FieldState(
            value: current,
            onChanged: (v) {
              setState(() => current = v);
              onChanged?.call(v);
            },
            enabled: enabled,
            error: error,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('parsing', () {
    test('reads all four gates and both labels off config', () {
      final component =
          keyvalueField(
                'meta',
                addable: false,
                deletable: true,
                editableKeys: false,
                editableValues: true,
                keyLabel: 'Attribute',
                valueLabel: 'Detail',
              )
              as KeyValueComponent;

      expect(component.addable, isFalse);
      expect(component.deletable, isTrue);
      expect(component.editableKeys, isFalse);
      expect(component.editableValues, isTrue);
      expect(component.keyLabel, 'Attribute');
      expect(component.valueLabel, 'Detail');
    });

    test(
      'an absent config reads all four gates as their vendor default of true',
      () {
        final component =
            SchemaComponent.fromJson({
                  'type': 'keyvalue',
                  'name': 'meta',
                }, 'form[0]')
                as KeyValueComponent;

        expect(component.addable, isTrue);
        expect(component.deletable, isTrue);
        expect(component.editableKeys, isTrue);
        expect(component.editableValues, isTrue);
      },
    );
  });

  // Two pairs, not one, throughout: a fixture with a single pair can never
  // show pair 2's edit leaking into pair 1 — the flat-state bug this file
  // exists to catch. Distinct keys AND distinct values, so a transposition
  // bug (row 2's value landing under row 1's key) is visible too.
  const twoPairs = {'env': 'staging', 'region': 'eu'};

  testWidgets('dispatches to KeyValueFieldWidget, one row per pair', (
    tester,
  ) async {
    await tester.pumpWidget(
      keyvalueHarness(component: keyvalueField('meta'), value: twoPairs),
    );

    expect(find.byType(KeyValueFieldWidget), findsOneWidget);
    expect(find.byKey(const ValueKey('keyvalue.meta.row.0')), findsOneWidget);
    expect(find.byKey(const ValueKey('keyvalue.meta.row.1')), findsOneWidget);
    expect(find.text('env'), findsOneWidget);
    expect(find.text('staging'), findsOneWidget);
    expect(find.text('region'), findsOneWidget);
    expect(find.text('eu'), findsOneWidget);
  });

  testWidgets('editing pair 2\'s value leaves pair 1 untouched', (
    tester,
  ) async {
    Object? received;
    await tester.pumpWidget(
      keyvalueHarness(
        component: keyvalueField('meta'),
        value: twoPairs,
        onChanged: (v) => received = v,
      ),
    );

    final valueFields = find.descendant(
      of: find.byKey(const ValueKey('keyvalue.meta.row.1')),
      matching: find.byType(TextField),
    );
    // The value input is the second TextField in the row.
    await tester.enterText(valueFields.at(1), 'de');
    await tester.pump();

    expect(received, {'env': 'staging', 'region': 'de'});
  });

  testWidgets('editing pair 1\'s key leaves pair 2 untouched', (tester) async {
    Object? received;
    await tester.pumpWidget(
      keyvalueHarness(
        component: keyvalueField('meta'),
        value: twoPairs,
        onChanged: (v) => received = v,
      ),
    );

    final keyFields = find.descendant(
      of: find.byKey(const ValueKey('keyvalue.meta.row.0')),
      matching: find.byType(TextField),
    );
    await tester.enterText(keyFields.first, 'environment');
    await tester.pump();

    expect(received, {'environment': 'staging', 'region': 'eu'});
  });

  testWidgets('adding a pair appends without disturbing the others', (
    tester,
  ) async {
    Object? received;
    await tester.pumpWidget(
      keyvalueHarness(
        component: keyvalueField('meta'),
        value: twoPairs,
        onChanged: (v) => received = v,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('keyvalue.meta.add')));
    await tester.pump();

    expect(received, {'env': 'staging', 'region': 'eu', '': ''});
  });

  testWidgets('removing pair 1 leaves pair 2 intact', (tester) async {
    Object? received;
    await tester.pumpWidget(
      keyvalueHarness(
        component: keyvalueField('meta'),
        value: twoPairs,
        onChanged: (v) => received = v,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('keyvalue.meta.remove.0')));
    await tester.pump();

    expect(received, {'region': 'eu'});
  });

  // Four gates, four independently-named tests. Each flips exactly one gate
  // false against a shared harness and asserts exactly the affordance that
  // gate owns is gone while the field's data is unaffected — so a mutation
  // that hardcodes any one gate to `true` in KeyValueFieldWidget reds only
  // the test naming that gate, never the others. See the class doc's
  // "absent, not disabled" split: addable/deletable remove a control
  // outright, editableKeys/editableValues merely disable one.

  testWidgets('addable == false removes the Add affordance only', (
    tester,
  ) async {
    await tester.pumpWidget(
      keyvalueHarness(
        component: keyvalueField('meta', addable: false),
        value: twoPairs,
      ),
    );

    expect(find.byKey(const ValueKey('keyvalue.meta.add')), findsNothing);
    // Every other affordance this fixture's other gates would enable stays.
    expect(
      find.byKey(const ValueKey('keyvalue.meta.remove.0')),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .every((f) => f.enabled == true),
      isTrue,
    );
  });

  testWidgets(
    'deletable == false removes every row\'s Remove affordance only',
    (tester) async {
      await tester.pumpWidget(
        keyvalueHarness(
          component: keyvalueField('meta', deletable: false),
          value: twoPairs,
        ),
      );

      expect(
        find.byKey(const ValueKey('keyvalue.meta.remove.0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('keyvalue.meta.remove.1')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('keyvalue.meta.add')), findsOneWidget);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((f) => f.enabled == true),
        isTrue,
      );
    },
  );

  // Fix round 1, Finding 1: "absent, not disabled" was implemented as
  // disabled — a gated key/value input rendered as a focusable, inert
  // TextField instead of going away. The input AFFORDANCE is now absent
  // (plain, unfocusable Text); the value itself is never absent, since the
  // row still has to show what it holds.
  testWidgets(
    'editableKeys == false renders the key as plain text, not an input',
    (tester) async {
      await tester.pumpWidget(
        keyvalueHarness(
          component: keyvalueField('meta', editableKeys: false),
          value: twoPairs,
        ),
      );

      final keyCell = find.byKey(const ValueKey('keyvalue.meta.key.0'));
      expect(
        find.descendant(of: keyCell, matching: find.byType(TextField)),
        findsNothing,
      );
      expect(
        find.descendant(of: keyCell, matching: find.text('env')),
        findsOneWidget,
      );

      // The value cell is untouched by this gate.
      final valueCell = find.byKey(const ValueKey('keyvalue.meta.value.0'));
      expect(
        find.descendant(of: valueCell, matching: find.byType(TextField)),
        findsOneWidget,
      );

      // Add/Remove are untouched by this gate.
      expect(find.byKey(const ValueKey('keyvalue.meta.add')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('keyvalue.meta.remove.0')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'editableValues == false renders the value as plain text, not an input',
    (tester) async {
      await tester.pumpWidget(
        keyvalueHarness(
          component: keyvalueField('meta', editableValues: false),
          value: twoPairs,
        ),
      );

      final valueCell = find.byKey(const ValueKey('keyvalue.meta.value.0'));
      expect(
        find.descendant(of: valueCell, matching: find.byType(TextField)),
        findsNothing,
      );
      expect(
        find.descendant(of: valueCell, matching: find.text('staging')),
        findsOneWidget,
      );

      final keyCell = find.byKey(const ValueKey('keyvalue.meta.key.0'));
      expect(
        find.descendant(of: keyCell, matching: find.byType(TextField)),
        findsOneWidget,
      );

      expect(find.byKey(const ValueKey('keyvalue.meta.add')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('keyvalue.meta.remove.0')),
        findsOneWidget,
      );
    },
  );

  // Fix round 1, Finding 2: row identity was the key string itself, so a
  // second Add's blank key collided with the first (silent no-op) and
  // renaming one row's key to another's silently deleted a row mid-edit.
  testWidgets('tapping Add twice creates two distinct blank rows, not one', (
    tester,
  ) async {
    await tester.pumpWidget(
      keyvalueHarness(
        component: keyvalueField('meta'),
        value: const {'env': 'staging'},
      ),
    );

    await tester.tap(find.byKey(const ValueKey('keyvalue.meta.add')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('keyvalue.meta.add')));
    await tester.pump();

    // Three rows in the tree — the second tap is not a no-op just because
    // both new rows happen to share the blank key.
    expect(find.byKey(const ValueKey('keyvalue.meta.row.0')), findsOneWidget);
    expect(find.byKey(const ValueKey('keyvalue.meta.row.1')), findsOneWidget);
    expect(find.byKey(const ValueKey('keyvalue.meta.row.2')), findsOneWidget);
  });

  testWidgets(
    'renaming a key to collide with another row keeps both rows visible',
    (tester) async {
      await tester.pumpWidget(
        keyvalueHarness(
          component: keyvalueField('meta'),
          value: const {'a': '1', 'b': '2'},
        ),
      );

      final row1KeyField = find
          .descendant(
            of: find.byKey(const ValueKey('keyvalue.meta.row.1')),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(row1KeyField, 'a');
      await tester.pump();

      // Both rows survive the collision — row 0's original value ('1') is
      // still on screen, not silently dropped while the user is mid-edit.
      expect(find.byKey(const ValueKey('keyvalue.meta.row.0')), findsOneWidget);
      expect(find.byKey(const ValueKey('keyvalue.meta.row.1')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    },
  );

  testWidgets('enabled == false is inert regardless of the server\'s gates', (
    tester,
  ) async {
    Object? received;
    await tester.pumpWidget(
      keyvalueHarness(
        component: keyvalueField('meta'),
        value: twoPairs,
        enabled: false,
        onChanged: (v) => received = v,
      ),
    );

    expect(find.byKey(const ValueKey('keyvalue.meta.add')), findsNothing);
    expect(find.byKey(const ValueKey('keyvalue.meta.remove.0')), findsNothing);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .every((f) => f.enabled != true),
      isTrue,
    );
    expect(received, isNull);

    // Every pair still renders — inert is not invisible.
    for (final entry in twoPairs.entries) {
      expect(find.text(entry.key), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('shows the field error', (tester) async {
    await tester.pumpWidget(
      keyvalueHarness(
        component: keyvalueField('meta'),
        value: twoPairs,
        error: 'Too many pairs.',
      ),
    );

    expect(find.text('Too many pairs.'), findsOneWidget);
  });

  testWidgets('a null value renders zero rows, not a crash', (tester) async {
    await tester.pumpWidget(
      keyvalueHarness(component: keyvalueField('meta'), value: null),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(KeyValueFieldWidget), findsOneWidget);
    expect(find.byKey(const ValueKey('keyvalue.meta.row.0')), findsNothing);
  });
}
