import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SchemaComponent remoteSelect(String name) => SchemaComponent.fromJson({
  'type': 'select',
  'name': name,
  'label': name,
  'config': {'optionsUrl': '/api/mobile-panel/banners/options'},
}, 'form[0]');

SchemaComponent remoteMultiSelect(String name) => SchemaComponent.fromJson({
  'type': 'select',
  'name': name,
  'label': name,
  'config': {
    'optionsUrl': '/api/mobile-panel/banners/options',
    'multiple': true,
  },
}, 'form[0]');

Widget harness({
  required SchemaComponent component,
  required FieldState state,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) =>
            FieldRegistry.defaults().build(context, component, state),
      ),
    ),
  );
}

/// A select whose options `/schema` withheld.
///
/// The node carries `config.optionsUrl` and no `config.options`, so there is
/// nothing to put in a dropdown until the user searches.
void main() {
  const acme = SelectOption(value: 3, label: 'Acme Ltd');

  testWidgets('renders the stored value before any fetch', (tester) async {
    // On an edit form the stored foreign key arrives before any search has
    // run. Blanking it would discard what the record holds behind a
    // working-looking screen — the failure shape this project keeps closing.
    await tester.pumpWidget(
      harness(
        component: remoteSelect('company_id'),
        state: FieldState(
          value: 3,
          onChanged: (_) {},
          searchOptions: (_) async => const OptionsPage.empty(),
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('searches on open and again as the user types', (tester) async {
    final queries = <String>[];

    await tester.pumpWidget(
      harness(
        component: remoteSelect('company_id'),
        state: FieldState(
          value: null,
          onChanged: (_) {},
          searchOptions: (query) async {
            queries.add(query);
            return const OptionsPage(options: [acme], hasMore: false);
          },
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    // An empty query on open, so the sheet is not blank before the user types.
    expect(queries, ['']);

    await tester.enterText(
      find.byKey(const ValueKey('options.search')),
      'acme',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(queries.last, 'acme');
  });

  testWidgets('reports the chosen option value, not its label', (tester) async {
    // The contract allows int values with string labels; sending the label
    // back is the classic bug in a picker.
    Object? received;

    await tester.pumpWidget(
      harness(
        component: remoteSelect('company_id'),
        state: FieldState(
          value: null,
          onChanged: (value) => received = value,
          searchOptions: (_) async =>
              const OptionsPage(options: [acme], hasMore: false),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('options.item.3')));
    await tester.pumpAndSettle();

    expect(received, 3);
  });

  testWidgets('says the list was cut short when hasMore', (tester) async {
    // Implying a truncated list is complete is how a user concludes their
    // record does not exist.
    await tester.pumpWidget(
      harness(
        component: remoteSelect('company_id'),
        state: FieldState(
          value: null,
          onChanged: (_) {},
          searchOptions: (_) async =>
              const OptionsPage(options: [acme], hasMore: true),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('options.hasMore')), findsOneWidget);
  });

  testWidgets('does not say so when the list is complete', (tester) async {
    // The counter-test: a widget that always showed the hint would pass the
    // one above while telling every user their list is incomplete.
    await tester.pumpWidget(
      harness(
        component: remoteSelect('company_id'),
        state: FieldState(
          value: null,
          onChanged: (_) {},
          searchOptions: (_) async =>
              const OptionsPage(options: [acme], hasMore: false),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('options.hasMore')), findsNothing);
  });

  testWidgets('shows an honest empty state after a successful empty search', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        component: remoteSelect('company_id'),
        state: FieldState(
          value: null,
          onChanged: (_) {},
          searchOptions: (_) async => const OptionsPage.empty(),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('shows failure and retries the same query', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      harness(
        component: remoteSelect('company_id'),
        state: FieldState(
          value: null,
          onChanged: (_) {},
          searchOptions: (_) async {
            if (calls++ == 0) throw Exception('offline');
            return const OptionsPage(options: [acme], hasMore: false);
          },
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(find.text('Could not load'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('options.retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('options.item.3')), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('multiple remote selection stays open until Save', (
    tester,
  ) async {
    Object? received;
    await tester.pumpWidget(
      harness(
        component: remoteMultiSelect('companies'),
        state: FieldState(
          value: const [2],
          onChanged: (value) => received = value,
          searchOptions: (_) async => const OptionsPage(
            options: [
              SelectOption(value: 2, label: 'Beta'),
              SelectOption(value: 3, label: 'Acme Ltd'),
            ],
            hasMore: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('options.item.3')));
    await tester.pump();

    expect(find.byKey(const ValueKey('options.search')), findsOneWidget);
    expect(received, isNull);

    await tester.tap(find.byKey(const ValueKey('options.save')));
    await tester.pumpAndSettle();

    expect(received, [2, 3]);
  });

  testWidgets('a disabled remote select does not open', (tester) async {
    // enabled: false must make the control inert, not merely grey. A picker
    // that looks disabled and still opens is how a refused value reaches a
    // payload.
    var searched = false;

    await tester.pumpWidget(
      harness(
        component: remoteSelect('company_id'),
        state: FieldState(
          value: null,
          onChanged: (_) {},
          enabled: false,
          searchOptions: (_) async {
            searched = true;
            return const OptionsPage.empty();
          },
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(searched, isFalse);
    expect(find.byKey(const ValueKey('options.search')), findsNothing);
  });

  testWidgets('falls back to an inline dropdown when no optionsUrl', (
    tester,
  ) async {
    // The trigger is the URL, not the type: a select whose options `/schema`
    // did inline must keep rendering as a dropdown.
    await tester.pumpWidget(
      harness(
        component: SchemaComponent.fromJson({
          'type': 'select',
          'name': 'status',
          'label': 'status',
          'config': {
            'options': [
              {'value': 'a', 'label': 'A'},
            ],
          },
        }, 'form[0]'),
        state: FieldState(value: null, onChanged: (_) {}),
      ),
    );

    expect(find.byType(DropdownButtonFormField<Object?>), findsOneWidget);
  });
}
