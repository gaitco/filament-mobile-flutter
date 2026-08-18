import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/form/fields/field_widgets.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsed through the real [SchemaComponent.fromJson], the same discipline
/// radio_field_test.dart documents — a hand-built [ToggleButtonsComponent]
/// is impossible from here anyway (the constructor is library-private).
SchemaComponent toggleButtonsField(
  String name, {
  required Map<Object, String> options,
  bool multiple = false,
  Object? defaultValue,
}) => SchemaComponent.fromJson({
  'type': 'toggle_buttons',
  'name': name,
  'label': name,
  if (defaultValue != null) 'default': defaultValue,
  'config': {
    'multiple': multiple,
    'options': [
      for (final entry in options.entries)
        {'value': entry.key, 'label': entry.value},
    ],
  },
}, 'form[0]');

/// The same `StatefulBuilder` harness radio_field_test.dart uses, for the
/// same reason: a non-rebuilding harness can report the right value on tap
/// without ever proving the PREVIOUS selection was dropped.
Widget toggleButtonsHarness({
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

ChoiceChip chip(WidgetTester tester, String label) => tester.widget<ChoiceChip>(
  find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip)),
);

FilterChip filterChip(WidgetTester tester, String label) =>
    tester.widget<FilterChip>(
      find.ancestor(of: find.text(label), matching: find.byType(FilterChip)),
    );

void main() {
  // Two options throughout, never one — radio_field_test.dart's rule: a
  // one-option fixture cannot distinguish "renders the selected one" from
  // "renders the only one".
  final twoOptions = {'draft': 'Draft', 'live': 'Live'};

  testWidgets('dispatches to ToggleButtonsFieldWidget, one chip per option', (
    tester,
  ) async {
    await tester.pumpWidget(
      toggleButtonsHarness(
        component: toggleButtonsField('status', options: twoOptions),
      ),
    );

    expect(find.byType(ToggleButtonsFieldWidget), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets('single: tapping an option writes the scalar and drops the '
      'previous selection', (tester) async {
    Object? received;
    await tester.pumpWidget(
      toggleButtonsHarness(
        component: toggleButtonsField('status', options: twoOptions),
        value: 'draft',
        onChanged: (v) => received = v,
      ),
    );

    expect(chip(tester, 'Draft').selected, isTrue);
    expect(chip(tester, 'Live').selected, isFalse);

    await tester.tap(find.text('Live'));
    await tester.pump();

    expect(received, 'live');
    expect(chip(tester, 'Draft').selected, isFalse);
    expect(chip(tester, 'Live').selected, isTrue);
  });

  testWidgets('multiple: tapping writes a List, re-tapping removes', (
    tester,
  ) async {
    Object? received;
    await tester.pumpWidget(
      toggleButtonsHarness(
        component: toggleButtonsField(
          'flags',
          options: twoOptions,
          multiple: true,
        ),
        value: const ['draft'],
        onChanged: (v) => received = v,
      ),
    );

    expect(filterChip(tester, 'Draft').selected, isTrue);
    expect(filterChip(tester, 'Live').selected, isFalse);

    await tester.tap(find.text('Live'));
    await tester.pump();

    expect(received, ['draft', 'live']);
    expect(filterChip(tester, 'Live').selected, isTrue);

    await tester.tap(find.text('Draft'));
    await tester.pump();

    expect(received, ['live']);
    expect(filterChip(tester, 'Draft').selected, isFalse);
  });

  testWidgets('enabled == false renders inert with no selection possible', (
    tester,
  ) async {
    Object? received;
    await tester.pumpWidget(
      toggleButtonsHarness(
        component: toggleButtonsField('status', options: twoOptions),
        value: 'draft',
        enabled: false,
        onChanged: (v) => received = v,
      ),
    );

    await tester.tap(find.text('Live'));
    await tester.pump();

    expect(received, isNull);
    expect(
      chip(tester, 'Draft').selected,
      isTrue,
      reason: 'a disabled toggle-buttons field must not change on tap',
    );
  });

  testWidgets('shows the field error', (tester) async {
    await tester.pumpWidget(
      toggleButtonsHarness(
        component: toggleButtonsField('status', options: twoOptions),
        error: 'Choose a status.',
      ),
    );

    expect(find.text('Choose a status.'), findsOneWidget);
  });
}
