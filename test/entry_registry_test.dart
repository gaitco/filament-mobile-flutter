import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/ui/bidi_text.dart';
import 'package:filament_mobile/ui/entries/entry_widgets.dart';
import 'package:filament_mobile/ui/entry_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SchemaComponent parse(Map<String, dynamic> json) =>
    SchemaComponent.fromJson(json, 'infolist[0]');

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

ResourceRecord get _record => ResourceRecord.fromJson(const {
  'id': 1,
  'name': 'أحمد',
  'is_active': true,
  'status': 'active',
  'created_at': '2026-08-03',
}, 'id');

void main() {
  testWidgets('renders a text entry with its label and value', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => EntryRegistry.defaults().build(
            context,
            parse(const {
              'type': 'text_entry',
              'name': 'name',
              'label': 'الاسم',
            }),
            _record,
          ),
        ),
      ),
    );

    expect(find.text('الاسم'), findsOneWidget);
    expect(find.text('أحمد'), findsOneWidget);
  });

  testWidgets('a targeted entry taps through to its related record, and '
      'stays inert when any half is missing', (tester) async {
    const targeted = {
      'type': 'text_entry',
      'name': 'category.name',
      'label': 'Category',
      'config': {
        'target': {'resource': 'categories', 'record': 'category.id'},
      },
    };
    final record = ResourceRecord.fromJson(const {
      'id': 1,
      'category': {'name': 'Toys', 'id': 6},
    }, 'id');

    // Server target + record id + host callback: taps through.
    (String, Object)? tapped;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => EntryRegistry.defaults(
            onRelatedTap: (resource, id) => tapped = (resource, id),
          ).build(context, parse(targeted), record),
        ),
      ),
    );
    await tester.tap(find.text('Toys'));
    expect(tapped, ('categories', 6));

    // Host never wired it: plain tile, no tap target at all.
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) =>
              EntryRegistry.defaults().build(context, parse(targeted), record),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('entry.related.category.name')),
      findsNothing,
    );

    // Wired, but the payload carries no id (older server, null relation):
    // plain tile again.
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) =>
              EntryRegistry.defaults(
                onRelatedTap: (resource, id) => fail('must not fire'),
              ).build(
                context,
                parse(targeted),
                ResourceRecord.fromJson(const {
                  'id': 1,
                  'category': {'name': 'Toys'},
                }, 'id'),
              ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('entry.related.category.name')),
      findsNothing,
    );
  });

  testWidgets('renders a boolean entry as an icon, not raw true', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => EntryRegistry.defaults().build(
            context,
            parse(const {
              'type': 'boolean_entry',
              'name': 'is_active',
              'label': 'نشط',
            }),
            _record,
          ),
        ),
      ),
    );

    expect(find.text('نشط'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('true'), findsNothing);
  });

  testWidgets('recurses into a layout component', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => EntryRegistry.defaults().build(
            context,
            parse(const {
              'type': 'section',
              'label': 'البيانات',
              'children': [
                {'type': 'text_entry', 'name': 'name', 'label': 'الاسم'},
              ],
            }),
            _record,
          ),
        ),
      ),
    );

    expect(find.text('البيانات'), findsOneWidget);
    expect(find.text('أحمد'), findsOneWidget);
  });

  testWidgets('an unknown type renders nothing visible in release shape', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => EntryRegistry.defaults().build(
            context,
            parse(const {'type': 'signature_pad', 'name': 'sig'}),
            _record,
          ),
        ),
      ),
    );

    // Must never throw. In a debug build it shows a placeholder naming the
    // type; the assertion here is only that it degrades safely.
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown container still renders its children', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => EntryRegistry.defaults().build(
            context,
            parse(const {
              'type': 'wizard',
              'children': [
                {'type': 'text_entry', 'name': 'name', 'label': 'الاسم'},
                {'type': 'text_entry', 'name': 'status', 'label': 'الحالة'},
              ],
            }),
            _record,
          ),
        ),
      ),
    );

    // `wizard`, `split`, `flex` and `actions` all land on UnknownComponent.
    // Dropping their children would blank a whole branch of the screen — the
    // exact failure the parser keeps them for.
    expect(find.text('أحمد'), findsOneWidget);
    expect(find.text('active'), findsOneWidget);
  });

  testWidgets('a null value renders the entry without a crash', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => EntryRegistry.defaults().build(
            context,
            parse(const {
              'type': 'text_entry',
              'name': 'missing',
              'label': 'غائب',
            }),
            _record,
          ),
        ),
      ),
    );

    expect(find.text('غائب'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a registered custom type wins', (tester) async {
    final registry = EntryRegistry.defaults()
      ..register(
        'signature_pad',
        (context, component, record) => const Text('custom!'),
      );

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => registry.build(
            context,
            parse(const {'type': 'signature_pad', 'name': 'sig'}),
            _record,
          ),
        ),
      ),
    );

    expect(find.text('custom!'), findsOneWidget);
  });

  testWidgets('an image entry resolves the URL from a media sibling', (
    tester,
  ) async {
    final record = ResourceRecord.fromJson(const {
      'id': 1,
      'cover': 'uuid-1',
      'cover.__media': [
        {
          'uuid': 'uuid-1',
          'url': 'https://x/c.jpg',
          'thumbUrl': 'https://x/t.jpg',
        },
      ],
    }, 'id');

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => EntryRegistry.defaults().build(
            context,
            parse(const {
              'type': 'image_entry',
              'name': 'cover',
              'label': 'الغلاف',
            }),
            record,
          ),
        ),
      ),
    );

    final tile = tester.widget<ImageEntryTile>(find.byType(ImageEntryTile));
    expect(tile.url, 'https://x/t.jpg');
  });

  testWidgets('an image entry falls back to the raw string with no sibling', (
    tester,
  ) async {
    final record = ResourceRecord.fromJson(const {
      'id': 1,
      'photo': 'https://x/raw.jpg',
    }, 'id');

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => EntryRegistry.defaults().build(
            context,
            parse(const {
              'type': 'image_entry',
              'name': 'photo',
              'label': 'الصورة',
            }),
            record,
          ),
        ),
      ),
    );

    final tile = tester.widget<ImageEntryTile>(find.byType(ImageEntryTile));
    expect(tile.url, 'https://x/raw.jpg');
  });

  // Fix round 1, finding 2: `badge_entry` renders through `BadgeEntryTile` →
  // `SemanticBadge`, a fourth render seam the original pass missed —
  // `text_entry`'s value got isolated under RTL and `badge_entry`'s didn't,
  // for the same grouped-digit value. Isolation now lives inside
  // `SemanticBadge` itself (fix round 1), so both seams get it.
  testWidgets('a badge entry isolates its value under RTL', (tester) async {
    final record = ResourceRecord.fromJson(const {
      'id': 1,
      'lot': '+20 2 2411 8610',
    }, 'id');

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(
              builder: (context) => EntryRegistry.defaults().build(
                context,
                parse(const {
                  'type': 'badge_entry',
                  'name': 'lot',
                  'label': 'الدفعة',
                }),
                record,
              ),
            ),
          ),
        ),
      ),
    );

    final label = tester.widget<Text>(
      find.descendant(of: find.byType(Chip), matching: find.byType(Text)),
    );
    expect(label.data, isolateBidi('+20 2 2411 8610', TextDirection.rtl));
  });
}
