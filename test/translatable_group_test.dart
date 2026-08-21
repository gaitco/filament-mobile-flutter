import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/ui/resource_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/form_fixtures.dart';
import 'support/pump_until_found.dart';

/// A dotted `name`/`translatable` node, parsed through the real
/// [SchemaComponent.fromJson] like every other fixture in this suite — the
/// server publishes `translatable: true` only, so its absence below is
/// itself part of what the "non-translatable dotted field" test pins.
SchemaComponent node(String name, {bool translatable = false, String? label}) =>
    SchemaComponent.fromJson({
      'type': 'text',
      'name': name,
      'label': label ?? name,
      if (translatable) 'translatable': true,
    }, 'form');

Widget harness({
  required List<SchemaComponent> components,
  WriteResult writeResult = const WriteSuccess({}),
  List<String> locales = const [],
}) {
  final source = FakeSource(components: components, writeResult: writeResult);
  return MaterialApp(
    home: ResourceFormScreen(provider: providerFor(source, locales: locales)),
  );
}

void main() {
  testWidgets(
    'two translatable siblings render one visible field and two chips',
    (tester) async {
      await tester.pumpWidget(
        harness(
          components: [
            node('caption.ar', translatable: true),
            node('caption.en', translatable: true),
          ],
        ),
      );
      await pumpUntilFound(tester, find.byType(TextField));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(find.text('AR'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);
      // The group label is the humanized head attribute, not either
      // member's own "Ar"/"En" label.
      expect(find.text('Caption'), findsOneWidget);
    },
  );

  testWidgets('the chip picks which member renders, and both values survive in '
      'FormValues', (tester) async {
    final source = FakeSource(
      components: [
        node('caption.ar', translatable: true),
        node('caption.en', translatable: true),
      ],
    );
    final provider = providerFor(source);
    await tester.pumpWidget(
      MaterialApp(home: ResourceFormScreen(provider: provider)),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.enterText(
      find.byKey(const ValueKey('field.caption.ar')),
      'Arabic caption',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('locale-chip.caption.en')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('field.caption.ar')), findsNothing);
    expect(find.byKey(const ValueKey('field.caption.en')), findsOneWidget);
    // The hidden member's value is still there, even though its field
    // isn't the one on screen right now.
    expect(provider.values['caption.ar'], 'Arabic caption');

    await tester.enterText(
      find.byKey(const ValueKey('field.caption.en')),
      'English caption',
    );
    await tester.pump();

    expect(provider.values['caption.ar'], 'Arabic caption');
    expect(provider.values['caption.en'], 'English caption');
    // Every keystroke rebuilds through ListenableBuilder — the selection
    // must survive that rebuild rather than flip back to the first member.
    expect(find.byKey(const ValueKey('field.caption.en')), findsOneWidget);
  });

  testWidgets(
    'a 422 keyed to a hidden member force-switches the chip and shows the '
    'error',
    (tester) async {
      await tester.pumpWidget(
        harness(
          components: [
            node('caption.ar', translatable: true),
            node('caption.en', translatable: true),
          ],
          writeResult: const WriteInvalid({
            'caption.ar': ['Arabic caption is required.'],
          }),
        ),
      );
      await pumpUntilFound(tester, find.byType(TextField));

      // caption.ar is the first member, so it renders by default already —
      // switch to caption.en first so the error genuinely has to force the
      // chip back, not merely leave it where it started.
      await tester.tap(find.byKey(const ValueKey('locale-chip.caption.en')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field.caption.en')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('form.submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('field.caption.ar')), findsOneWidget);
      expect(find.byKey(const ValueKey('field.caption.en')), findsNothing);
      expect(find.text('Arabic caption is required.'), findsOneWidget);
    },
  );

  testWidgets(
    'errors on both members do not oscillate the visible chip across pumps',
    (tester) async {
      await tester.pumpWidget(
        harness(
          components: [
            node('name'),
            node('caption.ar', translatable: true),
            node('caption.en', translatable: true),
          ],
          writeResult: const WriteInvalid({
            'caption.ar': ['Arabic caption is required.'],
            'caption.en': ['English caption is required.'],
          }),
        ),
      );
      await pumpUntilFound(tester, find.byType(TextField));

      await tester.tap(find.byKey(const ValueKey('form.submit')));
      await tester.pumpAndSettle();

      // Both members already error, so whichever was visible before submit
      // (caption.ar, the first member) stays visible — there is nothing
      // hidden to reveal.
      expect(find.byKey(const ValueKey('field.caption.ar')), findsOneWidget);

      // Further rebuilds unrelated to either locale field (typing in `name`)
      // must not make the chip flip back and forth between the two errors.
      for (var i = 0; i < 3; i++) {
        await tester.enterText(
          find.byKey(const ValueKey('field.name')),
          'name-$i',
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('field.caption.ar')), findsOneWidget);
        expect(find.byKey(const ValueKey('field.caption.en')), findsNothing);
      }
    },
  );

  testWidgets(
    'a manual switch to the clean locale survives keystrokes while the '
    'other locale still errs',
    (tester) async {
      await tester.pumpWidget(
        harness(
          components: [
            node('name'),
            node('caption.ar', translatable: true),
            node('caption.en', translatable: true),
          ],
          writeResult: const WriteInvalid({
            'caption.ar': ['Arabic caption is required.'],
          }),
        ),
      );
      await pumpUntilFound(tester, find.byType(TextField));

      // Switch to `en` first, so `ar`'s error is genuinely hidden when the
      // submit force-switches back to it — same setup as the force-switch
      // test above.
      await tester.tap(find.byKey(const ValueKey('locale-chip.caption.en')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('form.submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field.caption.ar')), findsOneWidget);

      // The user deliberately switches back to the clean locale, `en` —
      // `ar`'s error is still there but no longer visible.
      await tester.tap(find.byKey(const ValueKey('locale-chip.caption.en')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field.caption.en')), findsOneWidget);

      // Neither `ar`'s stored error nor further unrelated keystrokes should
      // force the chip back to it — the manual pick sticks.
      for (var i = 0; i < 3; i++) {
        await tester.enterText(
          find.byKey(const ValueKey('field.name')),
          'name-$i',
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('field.caption.en')), findsOneWidget);
        expect(find.byKey(const ValueKey('field.caption.ar')), findsNothing);
      }
    },
  );

  testWidgets('a lone translatable field renders chipless', (tester) async {
    await tester.pumpWidget(
      harness(components: [node('caption.ar', translatable: true)]),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const ValueKey('field.caption.ar')), findsOneWidget);
  });

  testWidgets('a non-translatable dotted field renders as today', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(components: [node('caption.ar'), node('caption.en')]),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const ValueKey('field.caption.ar')), findsOneWidget);
    expect(find.byKey(const ValueKey('field.caption.en')), findsOneWidget);
  });

  testWidgets('chips are ordered by panel.locales when non-empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        components: [
          node('caption.ar', translatable: true),
          node('caption.en', translatable: true),
        ],
        locales: const ['en', 'ar'],
      ),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .toList();
    expect((chips[0].label as Text).data, 'EN');
    expect((chips[1].label as Text).data, 'AR');
  });

  testWidgets('the submission payload still carries every locale', (
    tester,
  ) async {
    final source = FakeSource(
      components: [
        node('caption.ar', translatable: true),
        node('caption.en', translatable: true),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: ResourceFormScreen(provider: providerFor(source))),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.enterText(
      find.byKey(const ValueKey('field.caption.ar')),
      'Arabic caption',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('locale-chip.caption.en')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('field.caption.en')),
      'English caption',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('form.submit')));
    await tester.pumpAndSettle();

    // FormValues.payloadFor already nests a dotted name — untouched by this
    // feature — so both locales surviving submission shows up as both keys
    // of the nested map, not two flat dotted keys.
    expect(source.lastPayload, {
      'caption': {'ar': 'Arabic caption', 'en': 'English caption'},
    });
  });

  testWidgets(
    'a non-grouped sibling interleaved between the two locale members does '
    'not disturb the group\'s position',
    (tester) async {
      // caption.en sits after `subtitle` in the schema — the group must
      // still render at caption.ar's (the first member's) position, with
      // `subtitle` rendering as its own field right after it, not
      // sandwiched between two locale fields.
      await tester.pumpWidget(
        harness(
          components: [
            node('name'),
            node('caption.ar', translatable: true),
            node('subtitle'),
            node('caption.en', translatable: true),
          ],
        ),
      );
      await pumpUntilFound(tester, find.byType(TextField));

      final nameY = tester
          .getTopLeft(find.byKey(const ValueKey('field.name')))
          .dy;
      final groupY = tester
          .getTopLeft(find.byKey(const ValueKey('group.caption')))
          .dy;
      final subtitleY = tester
          .getTopLeft(find.byKey(const ValueKey('field.subtitle')))
          .dy;

      expect(nameY, lessThan(groupY));
      expect(groupY, lessThan(subtitleY));
      expect(find.byKey(const ValueKey('field.caption.ar')), findsOneWidget);
      expect(find.byKey(const ValueKey('field.subtitle')), findsOneWidget);
    },
  );
}
