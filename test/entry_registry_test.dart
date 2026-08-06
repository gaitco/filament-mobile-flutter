import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/schema/schema_component.dart';
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
}
