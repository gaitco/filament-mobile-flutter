import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/ui/resource_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders every slot when all are present', (tester) async {
    await tester.pumpWidget(
      wrap(
        ResourceCard(
          layout: const CardLayout(
            titleField: 'name',
            subtitleField: 'company.name',
            badges: [
              CardBadge(field: 'status', colors: {'active': 'success'}),
            ],
            meta: [CardMeta(field: 'created_at')],
          ),
          record: ResourceRecord.fromJson(const {
            'id': 1,
            'name': 'اللافتة الأولى',
            'company': {'name': 'جيت'},
            'status': 'active',
            'created_at': '2026-08-03',
          }, 'id'),
        ),
      ),
    );

    expect(find.text('اللافتة الأولى'), findsOneWidget);
    expect(find.text('جيت'), findsOneWidget);
    expect(find.text('active'), findsOneWidget);
    // Formatted, not the raw ISO string: a timestamp printed verbatim puts
    // LTR digits and a `T` in the middle of an RTL card. The exact rendering
    // is the locale's, so this asserts only that the raw form is gone and a
    // date is shown.
    expect(find.text('2026-08-03'), findsNothing);
    expect(find.textContaining('2026'), findsOneWidget);
  });

  testWidgets('a title-only card renders without empty gaps', (tester) async {
    await tester.pumpWidget(
      wrap(
        ResourceCard(
          layout: const CardLayout(titleField: 'name'),
          record: ResourceRecord.fromJson(const {
            'id': 1,
            'name': 'وحيد',
          }, 'id'),
        ),
      ),
    );

    expect(find.text('وحيد'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('a null image falls back to initials, showing no error', (
    tester,
  ) async {
    // The pilot found media-library images serialise as null. This must look
    // intentional, not broken.
    await tester.pumpWidget(
      wrap(
        ResourceCard(
          layout: const CardLayout(
            titleField: 'name',
            leading: CardLeading(
              type: 'image',
              field: 'image_url',
              fallback: 'initials',
            ),
          ),
          record: ResourceRecord.fromJson(const {
            'id': 1,
            'name': 'أحمد',
            'image_url': null,
          }, 'id'),
        ),
      ),
    );

    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.text('أ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a media sibling feeds the leading image', (tester) async {
    final layout = CardLayout.fromJson(const {
      'title': {'field': 'name'},
      'leading': {'type': 'image', 'field': 'cover'},
    }, 'card');
    final record = ResourceRecord.fromJson(const {
      'id': 1,
      'name': 'Trip',
      'cover': 'uuid-1', // raw value is an opaque token, NOT a URL
      'cover.__media': [
        {
          'uuid': 'uuid-1',
          'url': 'https://x/c.jpg',
          'thumbUrl': 'https://x/t.jpg',
        },
      ],
    }, 'id');

    await tester.pumpWidget(wrap(ResourceCard(layout: layout, record: record)));

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect((avatar.backgroundImage as NetworkImage).url, 'https://x/t.jpg');
  });

  testWidgets(
    'a badge with no colour match renders neutrally with its raw value',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          ResourceCard(
            layout: const CardLayout(
              titleField: 'name',
              badges: [
                CardBadge(field: 'status', colors: {'active': 'success'}),
              ],
            ),
            record: ResourceRecord.fromJson(const {
              'id': 1,
              'name': 'x',
              'status': 'archived',
            }, 'id'),
          ),
        ),
      );

      expect(find.text('archived'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a boolean badge value renders as a check, never the word '
      '"true"', (tester) async {
    // HANDOFF's parked card-badge gap: a badge slot bound to a boolean
    // column used to print the literal word `true`. Detection is on the raw
    // typed value, so the string "true" below stays a text badge while the
    // bool gets Filament's boolean-column idiom.
    await tester.pumpWidget(
      wrap(
        ResourceCard(
          layout: const CardLayout(
            titleField: 'name',
            badges: [
              CardBadge(field: 'is_active', colors: {'1': 'success'}),
              CardBadge(field: 'note'),
            ],
          ),
          record: ResourceRecord.fromJson(const {
            'id': 1,
            'name': 'x',
            'is_active': true,
            'note': 'true',
          }, 'id'),
        ),
      ),
    );

    expect(find.byIcon(Icons.check), findsOneWidget);
    // The string "true" keeps the text treatment — only the bool changed.
    expect(find.text('true'), findsOneWidget);
  });

  testWidgets('a false boolean badge renders as a cross', (tester) async {
    await tester.pumpWidget(
      wrap(
        ResourceCard(
          layout: const CardLayout(
            titleField: 'name',
            badges: [CardBadge(field: 'is_active')],
          ),
          record: ResourceRecord.fromJson(const {
            'id': 1,
            'name': 'x',
            'is_active': false,
          }, 'id'),
        ),
      ),
    );

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('false'), findsNothing);
  });

  testWidgets('a field that resolves to null is simply omitted', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ResourceCard(
          layout: const CardLayout(
            titleField: 'name',
            subtitleField: 'company.name',
          ),
          record: ResourceRecord.fromJson(const {
            'id': 1,
            'name': 'x',
            'company': null,
          }, 'id'),
        ),
      ),
    );

    expect(find.text('x'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calls onTap', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      wrap(
        ResourceCard(
          layout: const CardLayout(titleField: 'name'),
          record: ResourceRecord.fromJson(const {'id': 1, 'name': 'x'}, 'id'),
          onTap: () => taps++,
        ),
      ),
    );

    await tester.tap(find.byType(ResourceCard));
    expect(taps, 1);
  });

  testWidgets('renders correctly in RTL', (tester) async {
    // `Directionality` alone is what drives RTL layout. Deliberately NOT using
    // GlobalMaterialLocalizations: it would need a flutter_localizations
    // dev dependency, and this package's whole point is adding none.
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ResourceCard(
              layout: const CardLayout(
                titleField: 'name',
                subtitleField: 'email',
              ),
              record: ResourceRecord.fromJson(const {
                'id': 1,
                'name': 'أحمد',
                'email': 'a@b.c',
              }, 'id'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('أحمد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Fix round 1, finding 1: `_text()` used to isolate a badge's value
  // *before* handing it to `SemanticBadge`, whose `colors[value]` lookup is
  // keyed on the raw server value. Under RTL, a badge value matching the
  // grouped-digit pattern (a lot number, an SKU) got isolated first, the
  // lookup key no longer matched, and the chip silently lost its colour —
  // green under LTR, theme-default grey under RTL, for the exact same data.
  testWidgets('a badge value with grouped digits keeps its colour under RTL', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ResourceCard(
              layout: const CardLayout(
                titleField: 'name',
                badges: [
                  CardBadge(field: 'lot', colors: {'12-34': 'success'}),
                ],
              ),
              record: ResourceRecord.fromJson(const {
                'id': 1,
                'name': 'x',
                'lot': '12-34',
              }, 'id'),
            ),
          ),
        ),
      ),
    );

    final chip = tester.widget<Chip>(find.byType(Chip));
    expect(
      chip.backgroundColor,
      isNotNull,
      reason:
          'colors["12-34"] must still resolve under RTL — the badge\'s '
          'displayed text may be isolated, but the colour lookup key '
          'must stay the raw server value',
    );
  });

  // Fix round 1, finding 3: `_text()`'s `formatDates` flag exists so only
  // `meta` reformats an ISO-8601-shaped string as a localised date — a
  // title or subtitle holding the same shape must print raw, exactly as it
  // did before this task touched `_text()`'s signature. Nothing pinned that
  // boundary; this reds if `formatDates`'s default is ever flipped to true.
  testWidgets('a date-shaped title is not reformatted, unlike meta', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ResourceCard(
          layout: const CardLayout(titleField: 'name'),
          record: ResourceRecord.fromJson(const {
            'id': 1,
            'name': '2026-08-03',
          }, 'id'),
        ),
      ),
    );

    expect(find.text('2026-08-03'), findsOneWidget);
  });
}
