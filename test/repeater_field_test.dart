import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/ui/resource_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/form_fixtures.dart';
import 'support/pump_until_found.dart';

/// A repeater over a single `sku` text child — everything else is the knob
/// each test turns. Parsed through the real [SchemaComponent.fromJson], the
/// same discipline every fixture in this suite follows, so this can never
/// drift from what the wire actually produces.
RepeaterComponent repeaterField({
  bool addable = true,
  bool deletable = true,
  bool readOnly = false,
  int? minItems,
  int? maxItems,
  bool requiredChild = false,
  String? defaultValue,
}) {
  return SchemaComponent.fromJson({
        'type': 'repeater',
        'name': 'line_items',
        'label': 'Line items',
        'children': [
          {
            'type': 'text',
            'name': 'sku',
            'label': 'SKU',
            if (requiredChild) 'rules': {'required': true},
            if (defaultValue != null) 'default': defaultValue,
          },
        ],
        'config': {
          'addable': addable,
          'deletable': deletable,
          'readOnly': readOnly,
          if (minItems != null) 'minItems': minItems,
          if (maxItems != null) 'maxItems': maxItems,
        },
      }, 'test')
      as RepeaterComponent;
}

/// The same `harness()` pattern `field_registry_test.dart` uses for every
/// other field type — `FieldRegistry.defaults().build(...)` inside a bare
/// `MaterialApp`/`Scaffold` — wrapped in a `StatefulBuilder` so a rebuild
/// after `onChanged` is visible to the next interaction. A repeater is the
/// first field type whose own tests need more than one step (add, then
/// check the count; edit, then check the sibling row), which no existing
/// field needed. `rows` lives outside `builder` so it survives a `setState`,
/// not reset by it.
Widget repeaterHarness({
  required RepeaterComponent component,
  required List<Map<String, Object?>> rows,
  bool enabled = true,
  Map<String, String> errors = const {},
  ValueChanged<List<Object?>>? onChanged,
}) {
  var current = rows;
  return MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => FieldRegistry.defaults().build(
          context,
          component,
          FieldState(
            value: current,
            onChanged: (v) {
              final next = (v as List).cast<Map<String, Object?>>();
              setState(() => current = next);
              onChanged?.call(v);
            },
            enabled: enabled,
            errors: errors,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'a template field nested under a section still renders and reports — '
    'children is the same shape layout components already use, so the row '
    'walk must recurse the same way the top-level form does',
    (tester) async {
      final component =
          SchemaComponent.fromJson({
                'type': 'repeater',
                'name': 'line_items',
                'children': [
                  {
                    'type': 'section',
                    'children': [
                      {'type': 'text', 'name': 'sku', 'label': 'SKU'},
                    ],
                  },
                ],
                'config': {
                  'addable': true,
                  'deletable': true,
                  'readOnly': false,
                },
              }, 'test')
              as RepeaterComponent;
      List<Object?>? received;

      await tester.pumpWidget(
        repeaterHarness(
          component: component,
          rows: [
            {'sku': 'a'},
          ],
          onChanged: (v) => received = v,
        ),
      );

      expect(find.text('a'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'b');

      expect(received, [
        {'sku': 'b'},
      ]);
    },
  );

  testWidgets(
    '1: one card renders per row, each showing the template\'s fields with '
    'that row\'s own values',
    (tester) async {
      await tester.pumpWidget(
        repeaterHarness(
          component: repeaterField(),
          rows: [
            {'sku': 'a'},
            {'sku': 'b'},
          ],
        ),
      );

      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    },
  );

  group('2: Add', () {
    testWidgets('appears when addable and under maxItems', (tester) async {
      await tester.pumpWidget(
        repeaterHarness(
          component: repeaterField(maxItems: 2),
          rows: [
            {'sku': 'a'},
          ],
        ),
      );

      expect(find.byKey(const ValueKey('repeater.add')), findsOneWidget);
    });

    testWidgets('is absent at the cap', (tester) async {
      await tester.pumpWidget(
        repeaterHarness(
          component: repeaterField(maxItems: 2),
          rows: [
            {'sku': 'a'},
            {'sku': 'b'},
          ],
        ),
      );

      expect(find.byKey(const ValueKey('repeater.add')), findsNothing);
    });

    testWidgets('tapping it appends a row', (tester) async {
      await tester.pumpWidget(
        repeaterHarness(
          component: repeaterField(),
          rows: [
            {'sku': 'a'},
          ],
        ),
      );

      await tester.tap(find.byKey(const ValueKey('repeater.add')));
      await tester.pump();

      expect(find.byType(Card), findsNWidgets(2));
    });
  });

  group('3: Remove', () {
    testWidgets('appears per row when deletable and above minItems', (
      tester,
    ) async {
      await tester.pumpWidget(
        repeaterHarness(
          component: repeaterField(minItems: 1),
          rows: [
            {'sku': 'a'},
            {'sku': 'b'},
          ],
        ),
      );

      expect(find.byKey(const ValueKey('repeater.remove.0')), findsOneWidget);
      expect(find.byKey(const ValueKey('repeater.remove.1')), findsOneWidget);
    });

    testWidgets('is absent at the floor', (tester) async {
      await tester.pumpWidget(
        repeaterHarness(
          component: repeaterField(minItems: 1),
          rows: [
            {'sku': 'a'},
          ],
        ),
      );

      expect(find.byKey(const ValueKey('repeater.remove.0')), findsNothing);
    });

    testWidgets('tapping it removes that row, not another one', (tester) async {
      List<Object?>? received;
      await tester.pumpWidget(
        repeaterHarness(
          component: repeaterField(),
          rows: [
            {'sku': 'a'},
            {'sku': 'b'},
          ],
          onChanged: (v) => received = v,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('repeater.remove.0')));
      await tester.pump();

      expect(find.byType(Card), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(received, [
        {'sku': 'b'},
      ]);
    });
  });

  testWidgets(
    '4: editing a field in row 2 changes row 2 and leaves row 1 untouched — '
    'the flat-state bug shows up exactly as two rows sharing one value',
    (tester) async {
      List<Object?>? received;
      final row0 = {'sku': 'a'};
      final row1 = {'sku': 'b'};
      await tester.pumpWidget(
        repeaterHarness(
          component: repeaterField(),
          rows: [row0, row1],
          onChanged: (v) => received = v,
        ),
      );

      await tester.enterText(find.byType(TextField).at(1), 'edited');

      expect(received, isNotNull);
      final rows = received!.cast<Map<String, Object?>>();
      expect(rows[0]['sku'], 'a', reason: 'row 1 must not see row 2\'s edit');
      expect(rows[1]['sku'], 'edited');
    },
  );

  group('5: readOnly / disabled — the server\'s word wins', () {
    testWidgets(
      'component.readOnly renders rows inert with no Add/Remove even when '
      'state.enabled is true',
      (tester) async {
        Object? received;
        await tester.pumpWidget(
          repeaterHarness(
            component: repeaterField(readOnly: true, minItems: 0),
            rows: [
              {'sku': 'a'},
            ],
            enabled: true,
            onChanged: (v) => received = v,
          ),
        );

        expect(find.byKey(const ValueKey('repeater.add')), findsNothing);
        expect(find.byKey(const ValueKey('repeater.remove.0')), findsNothing);

        await tester.enterText(find.byType(TextField).first, 'crafted');
        expect(received, isNull);
      },
    );

    testWidgets(
      'state.enabled == false renders rows inert with no Add/Remove even '
      'when component.readOnly is false',
      (tester) async {
        Object? received;
        await tester.pumpWidget(
          repeaterHarness(
            component: repeaterField(minItems: 0),
            rows: [
              {'sku': 'a'},
            ],
            enabled: false,
            onChanged: (v) => received = v,
          ),
        );

        expect(find.byKey(const ValueKey('repeater.add')), findsNothing);
        expect(find.byKey(const ValueKey('repeater.remove.0')), findsNothing);

        await tester.enterText(find.byType(TextField).first, 'crafted');
        expect(received, isNull);
      },
    );
  });

  testWidgets(
    '6: a required child empty in row 2 blocks submission with the error '
    'on row 2, not a generic form error',
    (tester) async {
      final source = FakeSource(
        components: [repeaterField(requiredChild: true)],
      );
      await tester.pumpWidget(
        MaterialApp(home: ResourceFormScreen(provider: providerFor(source))),
      );
      await pumpUntilFound(tester, find.byKey(const ValueKey('repeater.add')));

      // Two rows: row 0 filled in, row 1 left empty.
      await tester.tap(find.byKey(const ValueKey('repeater.add')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('repeater.add')));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'ABC');

      await tester.tap(find.byKey(const ValueKey('form.submit')));
      await tester.pumpAndSettle();

      expect(
        source.writeCalls,
        0,
        reason:
            'a client-side hint may only delay a submission, but here it '
            'must, since the field is genuinely empty',
      );
      expect(find.text(const FilamentStrings().fieldRequired), findsOneWidget);
      // Row 0 is filled in and must show no error of its own.
      final row0Field = tester.widget<TextField>(find.byType(TextField).at(0));
      expect(row0Field.decoration?.errorText, isNull);
      // Anchored to row 1's own card, not merely present somewhere on
      // screen — a single message rendered for the whole repeater (outside
      // every card) would satisfy every expectation above without actually
      // naming which row is wrong.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('repeater.line_items.row.1')),
          matching: find.text(const FilamentStrings().fieldRequired),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '7: adding a row seeds the template\'s defaults — not an empty row that '
    'renders, validates and submits as three different things',
    (tester) async {
      final source = FakeSource(
        components: [
          repeaterField(requiredChild: true, defaultValue: 'SEEDED'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: ResourceFormScreen(provider: providerFor(source))),
      );
      await pumpUntilFound(tester, find.byKey(const ValueKey('repeater.add')));

      await tester.tap(find.byKey(const ValueKey('repeater.add')));
      await tester.pump();

      // Renders the default, not blank.
      expect(find.text('SEEDED'), findsOneWidget);

      // A required-but-defaulted row does not block the client gate...
      await tester.tap(find.byKey(const ValueKey('form.submit')));
      await tester.pumpAndSettle();

      // ...and what actually ships carries the same default the row showed.
      expect(source.writeCalls, 1);
      expect(source.lastPayload, {
        'line_items': [
          {'sku': 'SEEDED'},
        ],
      });
    },
  );

  testWidgets(
    '8: fixing row 2\'s own field clears row 2\'s own stale error — the '
    'provider\'s existing invariant, extended to a row-scoped key',
    (tester) async {
      final source = FakeSource(
        components: [repeaterField(requiredChild: true)],
      );
      await tester.pumpWidget(
        MaterialApp(home: ResourceFormScreen(provider: providerFor(source))),
      );
      await pumpUntilFound(tester, find.byKey(const ValueKey('repeater.add')));

      await tester.tap(find.byKey(const ValueKey('repeater.add')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('repeater.add')));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'ABC');

      await tester.tap(find.byKey(const ValueKey('form.submit')));
      await tester.pumpAndSettle();
      expect(find.text(const FilamentStrings().fieldRequired), findsOneWidget);

      // Fix row 1's own empty field.
      await tester.enterText(find.byType(TextField).at(1), 'FIXED');
      await tester.pump();

      expect(find.text(const FilamentStrings().fieldRequired), findsNothing);
    },
  );

  testWidgets(
    '9: a server 422 keyed \'line_items.1.sku\' lands on row 2, not the '
    'form banner — the authoritative twin of the client-side key shape',
    (tester) async {
      final source = FakeSource(
        components: [repeaterField()],
        writeResult: const WriteInvalid({
          'line_items.1.sku': ['Duplicate SKU.'],
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: ResourceFormScreen(provider: providerFor(source))),
      );
      await pumpUntilFound(tester, find.byKey(const ValueKey('repeater.add')));

      await tester.tap(find.byKey(const ValueKey('repeater.add')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('repeater.add')));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'A');
      await tester.enterText(find.byType(TextField).at(1), 'A');

      await tester.tap(find.byKey(const ValueKey('form.submit')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('repeater.line_items.row.1')),
          matching: find.text('Duplicate SKU.'),
        ),
        findsOneWidget,
        reason:
            'the authoritative server error must reach the row, not '
            'only the weaker client hint',
      );
      // Not also banked as a generic banner message.
      expect(find.text('Duplicate SKU.'), findsOneWidget);
    },
  );

  /// P6c close-out, ledger L17. A row used to build through a fresh
  /// `FieldRegistry.defaults()`, so a host's own field types — and its
  /// overrides of built-in ones — rendered everywhere on the form EXCEPT
  /// inside a repeater's rows. A silent inconsistency in a documented
  /// extension point, not a gap in an unsupported feature.
  testWidgets(
    'builds a row through the host registry, not a fresh default one',
    (tester) async {
      final registry = FieldRegistry.defaults()
        ..register('text', (context, component, state) => const Text('HOST'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => registry.build(
                context,
                repeaterField(),
                FieldState(
                  value: const [
                    {'sku': 'A'},
                  ],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('HOST'), findsOneWidget);
    },
  );
}
