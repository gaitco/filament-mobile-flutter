import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/form/fields/field_widgets.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsed through the real [SchemaComponent.fromJson], the same discipline
/// every fixture in this suite follows — a hand-built [SelectComponent]
/// could drift from what the wire (and the Laravel side's `radioNode()`
/// fixture) actually produces.
SchemaComponent radioField(
  String name, {
  required Map<Object, String> options,
}) => SchemaComponent.fromJson({
  'type': 'radio',
  'name': name,
  'label': name,
  'config': {
    'options': [
      for (final entry in options.entries)
        {'value': entry.key, 'label': entry.value},
    ],
  },
}, 'form[0]');

/// A `StatefulBuilder` wrapper, like `repeaterHarness` in
/// repeater_field_test.dart — a single non-rebuilding harness could report
/// the right value on tap without ever proving the PREVIOUS option actually
/// stopped being selected, which is exactly the gap this whole task exists
/// not to repeat.
Widget radioHarness({
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
  // Two options throughout, never one: a one-option fixture can't
  // distinguish "renders the selected one" from "renders the only one".
  final twoOptions = {'basic': 'Basic', 'pro': 'Pro'};

  testWidgets('dispatches to RadioFieldWidget, one row per option', (
    tester,
  ) async {
    await tester.pumpWidget(
      radioHarness(component: radioField('plan', options: twoOptions)),
    );

    expect(find.byType(RadioFieldWidget), findsOneWidget);
    expect(find.text('Basic'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
  });

  testWidgets('tapping an option selects it and deselects the previous one', (
    tester,
  ) async {
    Object? received;
    await tester.pumpWidget(
      radioHarness(
        component: radioField('plan', options: twoOptions),
        value: 'basic',
        onChanged: (v) => received = v,
      ),
    );

    // Basic starts selected — a single RadioGroup can only ever report one
    // groupValue, so this is also the proof that Pro starts NOT selected.
    expect(
      tester
          .widget<RadioGroup<Object?>>(find.byType(RadioGroup<Object?>))
          .groupValue,
      'basic',
    );

    await tester.tap(find.text('Pro'));
    await tester.pump();

    expect(received, 'pro');
    // The actual regression this guards: a naive per-tile boolean toggle
    // can select Pro while leaving Basic's own flag untouched, rendering
    // both as checked. One groupValue cannot hold two values, so this is
    // the deselection, not just the reported change.
    expect(
      tester
          .widget<RadioGroup<Object?>>(find.byType(RadioGroup<Object?>))
          .groupValue,
      'pro',
    );
  });

  testWidgets('enabled == false renders inert with no selection possible', (
    tester,
  ) async {
    Object? received;
    await tester.pumpWidget(
      radioHarness(
        component: radioField('plan', options: twoOptions),
        value: 'basic',
        enabled: false,
        onChanged: (v) => received = v,
      ),
    );

    await tester.tap(find.text('Pro'));
    await tester.pump();

    expect(received, isNull);
    expect(
      tester
          .widget<RadioGroup<Object?>>(find.byType(RadioGroup<Object?>))
          .groupValue,
      'basic',
      reason: 'a disabled radio group must not change selection on tap',
    );
  });

  testWidgets('shows the field error', (tester) async {
    await tester.pumpWidget(
      radioHarness(
        component: radioField('plan', options: twoOptions),
        error: 'Choose a plan.',
      ),
    );

    expect(find.text('Choose a plan.'), findsOneWidget);
  });
}
