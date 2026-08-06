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
}
