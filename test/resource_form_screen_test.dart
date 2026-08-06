import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/ui/resource_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/form_fixtures.dart';
import 'support/pump_until_found.dart';

Widget formHarness({
  FakeSource? source,
  List<SchemaComponent>? components,
  List<SchemaComponent>? stateResponse,
  WriteResult writeResult = const WriteSuccess({}),
  Object? recordId,
  TextDirection textDirection = TextDirection.ltr,
}) {
  final effectiveSource =
      source ??
      FakeSource(
        components: components ?? formWith(),
        stateResponse: stateResponse,
        writeResult: writeResult,
      );

  return MaterialApp(
    home: Directionality(
      textDirection: textDirection,
      child: ResourceFormScreen(
        provider: providerFor(effectiveSource, recordId: recordId),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the form, not a spinner, once loaded', (tester) async {
    // A fixed pump count is not a wait: this polls until the provider
    // reports success and fails on timeout rather than silently asserting
    // against a loading frame.
    await tester.pumpWidget(formHarness(components: formWith()));
    await pumpUntilFound(tester, find.byType(TextField));

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a hidden field is not rendered', (tester) async {
    await tester.pumpWidget(
      formHarness(components: formWith(hidden: 'city_id')),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    expect(find.text('City'), findsNothing);
  });

  testWidgets('a field revealed by /state appears without losing typed text', (
    tester,
  ) async {
    await tester.pumpWidget(
      formHarness(
        components: formWith(hidden: 'city_id', live: 'country_id'),
        stateResponse: formWith(reveal: 'city_id', live: 'country_id'),
      ),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.enterText(find.byKey(const ValueKey('field.name')), 'Sara');

    // country_id is `live` and a select — the change has to actually reach
    // provider.change() to trigger the /state round-trip, so this opens the
    // dropdown and picks an option rather than merely tapping the field
    // (which only opens the menu and calls nothing).
    await tester.tap(find.byKey(const ValueKey('field.country_id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('One').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('Sara'), findsOneWidget);
    expect(find.byKey(const ValueKey('field.city_id')), findsOneWidget);
  });

  testWidgets('the form banner shows an unmappable 422', (tester) async {
    await tester.pumpWidget(
      formHarness(
        components: formWith(),
        writeResult: const WriteInvalid({
          'tags.0.id': ['Invalid tag.'],
        }),
      ),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.tap(find.byKey(const ValueKey('form.submit')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid tag.'), findsOneWidget);
  });

  testWidgets('submitting twice fires one request', (tester) async {
    // A double-tap on a slow connection must not create two records. The
    // write is held open deliberately: `Future.value()` resolves fast enough
    // that two back-to-back taps can straddle a submission that has already
    // finished, which would pass this test for the wrong reason (the
    // provider's own re-entrancy guard, not the screen disabling its
    // control). Holding it open keeps the submitting window wide enough for
    // the second tap to actually land on a still-disabled button.
    final source = FakeSource(components: formWith())..holdNextWrite();
    await tester.pumpWidget(formHarness(source: source));
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.tap(find.byKey(const ValueKey('form.submit')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('form.submit')),
    );
    expect(button.onPressed, isNull, reason: 'submit must disable itself');

    await tester.tap(find.byKey(const ValueKey('form.submit')));
    source.completeHeldWrite();
    await tester.pumpAndSettle();

    expect(source.writeCalls, 1);
  });

  testWidgets('a 401 loading the edit record reaches PanelUnauthenticated, '
      'not a generic failure', (tester) async {
    // Sibling to the same regression on PanelIndexScreen, ResourceListScreen
    // and ResourceViewScreen. Edit mode only — recordId set, so load()
    // actually reads a record and has something to fail on.
    final source = FakeSource(
      components: formWith(),
      recordError: const FilamentTransportException(
        'Unauthenticated.',
        statusCode: 401,
      ),
    );
    await tester.pumpWidget(formHarness(source: source, recordId: 7));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('panel.unauthenticated')), findsOneWidget);
  });

  testWidgets('renders in RTL without overflow', (tester) async {
    await tester.pumpWidget(
      formHarness(components: formWith(), textDirection: TextDirection.rtl),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    expect(tester.takeException(), isNull);
  });
}
