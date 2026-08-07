import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/form/fields/field_widgets.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsed through the real [SchemaComponent.fromJson], the same discipline
/// every fixture in this suite follows — a hand-built [TagsComponent] could
/// drift from what the wire (and the Laravel side's `tagsNode()` fixture)
/// actually produces.
SchemaComponent tagsField(
  String name, {
  String? separator,
  List<String> suggestions = const [],
}) => SchemaComponent.fromJson({
  'type': 'tags',
  'name': name,
  'label': name,
  'config': {'separator': separator, 'suggestions': suggestions},
}, 'form[0]');

/// A `StatefulBuilder` wrapper, like `radioHarness` and `repeaterHarness`
/// before it: a non-rebuilding harness could report the right value on a
/// remove without ever proving the OTHER tags survived, which is the whole
/// point of the removal test below.
Widget tagsHarness({
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
    test('reads separator and suggestions off config', () {
      final component =
          tagsField(
                'labels',
                separator: ',',
                suggestions: const ['urgent', 'billing'],
              )
              as TagsComponent;

      expect(component.separator, ',');
      expect(component.suggestions, ['urgent', 'billing']);
    });

    test('a field with neither reads as no separator and no suggestions', () {
      // The server publishes `separator: null` for a TagsInput that never
      // called separator() — the value on the wire is a List<String> either
      // way, so the client has nothing to build from it.
      final component = tagsField('labels') as TagsComponent;

      expect(component.separator, isNull);
      expect(component.suggestions, isEmpty);
    });
  });

  // Three tags throughout, never two, and all distinct: a flat-state bug
  // shows up exactly as the WRONG tag vanishing, and a two-tag fixture
  // cannot tell "removed the right one" from "removed one of them".
  const three = ['urgent', 'billing', 'vip'];

  testWidgets('dispatches to TagsFieldWidget, one chip per tag', (
    tester,
  ) async {
    await tester.pumpWidget(
      tagsHarness(component: tagsField('labels'), value: three),
    );

    expect(find.byType(TagsFieldWidget), findsOneWidget);
    for (final tag in three) {
      expect(find.text(tag), findsOneWidget);
    }
  });

  testWidgets('committing on submit appends without disturbing the others', (
    tester,
  ) async {
    Object? received;
    await tester.pumpWidget(
      tagsHarness(
        component: tagsField('labels'),
        value: three,
        onChanged: (v) => received = v,
      ),
    );

    await tester.enterText(find.byType(TextField), 'new');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(received, ['urgent', 'billing', 'vip', 'new']);
  });

  testWidgets('removing tag 2 leaves tags 1 and 3 intact', (tester) async {
    Object? received;
    await tester.pumpWidget(
      tagsHarness(
        component: tagsField('labels'),
        value: three,
        onChanged: (v) => received = v,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('tags.labels.remove.1')));
    await tester.pump();

    // The exact surviving list, in order — not a length check, which a bug
    // that removed the wrong tag would pass.
    expect(received, ['urgent', 'vip']);
    expect(find.text('urgent'), findsOneWidget);
    expect(find.text('vip'), findsOneWidget);
    expect(find.text('billing'), findsNothing);
  });

  testWidgets('offers the suggestions the server published', (tester) async {
    Object? received;
    await tester.pumpWidget(
      tagsHarness(
        component: tagsField('labels', suggestions: const ['urgent', 'vip']),
        value: const ['urgent'],
        onChanged: (v) => received = v,
      ),
    );

    // `urgent` is already chosen, so only `vip` is left to offer — a
    // suggestion that re-adds a tag already on the field is a control that
    // does nothing.
    expect(
      find.byKey(const ValueKey('tags.labels.suggest.vip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tags.labels.suggest.urgent')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('tags.labels.suggest.vip')));
    await tester.pump();

    expect(received, ['urgent', 'vip']);
  });

  testWidgets('a field with no suggestions offers none', (tester) async {
    await tester.pumpWidget(
      tagsHarness(component: tagsField('labels'), value: three),
    );

    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('enabled == false is inert — no remove, no commit', (
    tester,
  ) async {
    Object? received;
    await tester.pumpWidget(
      tagsHarness(
        component: tagsField('labels', suggestions: const ['extra']),
        value: three,
        enabled: false,
        onChanged: (v) => received = v,
      ),
    );

    // The hard gate this whole file states up top: the control itself
    // refuses, not just its colours. No delete affordance at all, no
    // suggestion to tap, and the text field cannot be typed into.
    expect(find.byKey(const ValueKey('tags.labels.remove.1')), findsNothing);
    expect(
      find.byKey(const ValueKey('tags.labels.suggest.extra')),
      findsNothing,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(received, isNull);

    // Every tag still renders — inert is not invisible.
    for (final tag in three) {
      expect(find.text(tag), findsOneWidget);
    }
  });

  testWidgets('a blank or duplicate submission adds nothing', (tester) async {
    Object? received;
    await tester.pumpWidget(
      tagsHarness(
        component: tagsField('labels'),
        value: three,
        onChanged: (v) => received = v,
      ),
    );

    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(received, isNull);

    await tester.enterText(find.byType(TextField), 'billing');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(received, isNull);
  });

  testWidgets('shows the field error', (tester) async {
    await tester.pumpWidget(
      tagsHarness(
        component: tagsField('labels'),
        value: three,
        error: 'Too many tags.',
      ),
    );

    expect(find.text('Too many tags.'), findsOneWidget);
  });
}
