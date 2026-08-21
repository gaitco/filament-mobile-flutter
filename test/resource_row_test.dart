import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/ui/resource_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('ResourceRow', () {
    testWidgets('renders title, subtitle, every badge, every meta, and the '
        'leading image', (tester) async {
      await tester.pumpWidget(
        wrap(
          ResourceRow(
            layout: const CardLayout(
              titleField: 'name',
              subtitleField: 'company.name',
              leading: CardLeading(type: 'image', field: 'avatar'),
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
              'avatar': null,
            }, 'id'),
          ),
        ),
      );

      expect(find.text('اللافتة الأولى'), findsOneWidget);
      expect(find.text('جيت'), findsOneWidget);
      expect(find.text('active'), findsOneWidget);
      expect(find.textContaining('2026'), findsOneWidget);
      // No avatar url — falls back to the initials circle, same as
      // ResourceCard.
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('a very long title ellipsizes with no overflow at 600 wide', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
          ResourceRow(
            layout: const CardLayout(titleField: 'name'),
            record: ResourceRecord.fromJson({
              'id': 1,
              'name': 'a very long title ' * 20,
            }, 'id'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.byType(Text).first);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 1);
    });

    testWidgets('selected paints secondaryContainer', (tester) async {
      await tester.pumpWidget(
        wrap(
          ResourceRow(
            layout: const CardLayout(titleField: 'name'),
            record: ResourceRecord.fromJson(const {'id': 1, 'name': 'x'}, 'id'),
            selected: true,
          ),
        ),
      );

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(ResourceRow),
          matching: find.byType(Material),
        ),
      );
      final context = tester.element(find.byType(ResourceRow));
      expect(material.color, Theme.of(context).colorScheme.secondaryContainer);
    });

    testWidgets('not selected paints no background colour', (tester) async {
      await tester.pumpWidget(
        wrap(
          ResourceRow(
            layout: const CardLayout(titleField: 'name'),
            record: ResourceRecord.fromJson(const {'id': 1, 'name': 'x'}, 'id'),
          ),
        ),
      );

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(ResourceRow),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, isNull);
    });

    testWidgets('calls onTap', (tester) async {
      var taps = 0;

      await tester.pumpWidget(
        wrap(
          ResourceRow(
            layout: const CardLayout(titleField: 'name'),
            record: ResourceRecord.fromJson(const {'id': 1, 'name': 'x'}, 'id'),
            onTap: () => taps++,
          ),
        ),
      );

      await tester.tap(find.byType(ResourceRow));
      expect(taps, 1);
    });

    testWidgets('renders trailing', (tester) async {
      await tester.pumpWidget(
        wrap(
          ResourceRow(
            layout: const CardLayout(titleField: 'name'),
            record: ResourceRecord.fromJson(const {'id': 1, 'name': 'x'}, 'id'),
            trailing: const Icon(Icons.edit),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('RTL at 1200 puts the leading image on the right with no '
        'overflow', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
          ResourceRow(
            layout: const CardLayout(
              titleField: 'name',
              leading: CardLeading(type: 'image', field: 'avatar'),
            ),
            record: ResourceRecord.fromJson(const {
              'id': 1,
              'name': 'أحمد',
              'avatar': null,
            }, 'id'),
          ),
          direction: TextDirection.rtl,
        ),
      );

      expect(tester.takeException(), isNull);

      final rowLeft = tester.getTopLeft(find.byType(ResourceRow)).dx;
      final rowRight = tester.getTopRight(find.byType(ResourceRow)).dx;
      final avatarLeft = tester.getTopLeft(find.byType(CircleAvatar)).dx;

      // The leading edge under RTL is the right side of the row.
      expect(avatarLeft, greaterThan((rowLeft + rowRight) / 2));
    });

    group('narrow rows shed columns rather than squeeze them', () {
      const layout = CardLayout(
        titleField: 'name',
        subtitleField: 'summary',
        badges: [
          CardBadge(field: 'status', colors: {'Draft': 'warning'}),
        ],
        meta: [CardMeta(field: 'updated_at')],
      );
      final record = ResourceRecord.fromJson(const {
        'id': 1,
        'name': 'Wool Runner',
        'summary': 'Hand-loomed',
        'status': 'Draft',
        'updated_at': '2026-08-06T10:00:00Z',
      }, 'id');

      Future<void> pumpAt(WidgetTester tester, double width) =>
          tester.pumpWidget(
            wrap(
              SizedBox(
                width: width,
                child: ResourceRow(layout: layout, record: record),
              ),
            ),
          );

      testWidgets('a wide row shows every column', (tester) async {
        await pumpAt(tester, 700);

        expect(find.text('Draft'), findsOneWidget);
        expect(find.textContaining('2026'), findsOneWidget);
      });

      testWidgets('the date goes first — it cannot ellipsize usefully', (
        tester,
      ) async {
        await pumpAt(tester, 480);

        expect(find.text('Draft'), findsOneWidget);
        expect(find.textContaining('2026'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a phone-width row keeps only title and subtitle', (
        tester,
      ) async {
        await pumpAt(tester, 280);

        expect(find.text('Wool Runner'), findsOneWidget);
        expect(find.text('Draft'), findsNothing);
        expect(find.textContaining('2026'), findsNothing);
      });

      testWidgets('the header sheds exactly what the rows do', (tester) async {
        await tester.pumpWidget(
          wrap(
            const SizedBox(
              width: 480,
              child: ResourceRowHeader(layout: layout),
            ),
          ),
        );

        expect(find.text('Status'), findsOneWidget);
        expect(find.text('Updated at'), findsNothing);
      });
    });
  });

  group('ResourceRowHeader', () {
    testWidgets('shows humanised labels', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ResourceRowHeader(
            layout: CardLayout(
              titleField: 'name',
              subtitleField: 'category.name',
              badges: [CardBadge(field: 'status')],
              meta: [CardMeta(field: 'created_at')],
            ),
          ),
        ),
      );

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Category name'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Created at'), findsOneWidget);
    });

    testWidgets('a leading column gets a blank header cell, no crash', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const ResourceRowHeader(
            layout: CardLayout(
              titleField: 'name',
              leading: CardLeading(type: 'image', field: 'avatar'),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Name'), findsOneWidget);
    });
  });

  group('humanizeField', () {
    test('created_at → Created at', () {
      expect(humanizeField('created_at'), 'Created at');
    });

    test('category.name → Category name', () {
      expect(humanizeField('category.name'), 'Category name');
    });

    test('a single word is just capitalised', () {
      expect(humanizeField('status'), 'Status');
    });
  });
}
