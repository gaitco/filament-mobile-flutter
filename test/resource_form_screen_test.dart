import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/ui/resource_form_screen.dart';
import 'package:filament_mobile/ui/widget_slots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/expect_width_capped.dart';
import 'support/form_fixtures.dart';
import 'support/pump_until_found.dart';

Widget formHarness({
  FakeSource? source,
  List<SchemaComponent>? components,
  List<SchemaComponent>? stateResponse,
  WriteResult writeResult = const WriteSuccess({}),
  Object? recordId,
  TextDirection textDirection = TextDirection.ltr,
  FilamentWidgetRegistry? widgetRegistry,
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
        widgetRegistry: widgetRegistry,
      ),
    ),
  );
}

void main() {
  testWidgets('custom form slots surround fields and actions', (tester) async {
    final registry = FilamentWidgetRegistry();
    ResourceFormWidgetScope? receivedScope;
    Widget keyed(String key) => SizedBox(key: ValueKey(key), height: 8);

    registry
      ..register(FilamentWidgetSlot.resourceFormBeforeFields, (context, scope) {
        receivedScope = scope as ResourceFormWidgetScope;
        return keyed('slot.before-fields');
      })
      ..register(
        FilamentWidgetSlot.resourceFormAfterFields,
        (context, scope) => keyed('slot.after-fields'),
      )
      ..register(
        FilamentWidgetSlot.resourceFormBeforeActions,
        (context, scope) => keyed('slot.before-actions'),
      )
      ..register(
        FilamentWidgetSlot.resourceFormAfterActions,
        (context, scope) => keyed('slot.after-actions'),
      );

    await tester.pumpWidget(
      formHarness(components: formWith(), widgetRegistry: registry),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    expect(receivedScope?.resource.key, isNotEmpty);
    final beforeFields = tester
        .getTopLeft(find.byKey(const ValueKey('slot.before-fields')))
        .dy;
    final firstField = tester.getTopLeft(find.byType(TextField).first).dy;
    final afterFields = tester
        .getTopLeft(find.byKey(const ValueKey('slot.after-fields')))
        .dy;
    final beforeActions = tester
        .getTopLeft(find.byKey(const ValueKey('slot.before-actions')))
        .dy;
    final submit = tester
        .getTopLeft(find.byKey(const ValueKey('form.submit')))
        .dy;
    final afterActions = tester
        .getTopLeft(find.byKey(const ValueKey('slot.after-actions')))
        .dy;

    expect(beforeFields, lessThan(firstField));
    expect(firstField, lessThan(afterFields));
    expect(afterFields, lessThan(beforeActions));
    expect(beforeActions, lessThan(submit));
    expect(submit, lessThan(afterActions));
  });

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

  testWidgets('a successful save shows a Saved toast and pops the route', (
    tester,
  ) async {
    // The form is pushed from a list or a record; staying on a saved form
    // with nothing left to do is the web panel's behaviour only because the
    // web has a redirect the phone has no equivalent for. Pop + toast is that
    // redirect: the user lands back where they came from with confirmation.
    final source = FakeSource(components: formWith());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ResourceFormScreen(provider: providerFor(source)),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.tap(find.byKey(const ValueKey('form.submit')));
    await tester.pumpAndSettle();

    expect(find.byType(ResourceFormScreen), findsNothing, reason: 'popped');
    expect(find.text(const FilamentStrings().saved), findsOneWidget);
  });

  testWidgets('a failed save stays on the form with the banner', (
    tester,
  ) async {
    await tester.pumpWidget(
      formHarness(writeResult: const WriteFailed('Server exploded')),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.tap(find.byKey(const ValueKey('form.submit')));
    await tester.pumpAndSettle();

    expect(find.byType(ResourceFormScreen), findsOneWidget);
    expect(find.text('Server exploded'), findsOneWidget);
    expect(find.text(const FilamentStrings().saved), findsNothing);
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

  const constrained = ValueKey('resource-form-constrained-content');

  testWidgets(
    'at 1200px viewport, form content is width-constrained by default',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(formHarness(components: formWith()));
      await pumpUntilFound(tester, find.byType(TextField));

      expectWidthCapped(
        tester,
        find.byKey(constrained),
        cap: 720,
        viewportWidth: 1200,
      );
    },
  );

  testWidgets('at 400px viewport, form content is unconstrained by default', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(formHarness(components: formWith()));
    await pumpUntilFound(tester, find.byType(TextField));

    expect(find.byKey(constrained), findsNothing);
    expectFullWidth(
      tester,
      find
          .descendant(
            of: find.byType(ResourceFormScreen),
            matching: find.byType(ListView),
          )
          .first,
      viewportWidth: 400,
    );
  });

  testWidgets('explicit maxContentWidth is honored on form', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final source = FakeSource(components: formWith());
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: ResourceFormScreen(
            provider: providerFor(source),
            maxContentWidth: 500,
          ),
        ),
      ),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    // 500 < the 720 default: only an applied value can satisfy this.
    expectWidthCapped(
      tester,
      find.byKey(constrained),
      cap: 500,
      viewportWidth: 1200,
    );
  });

  testWidgets('onSaved replaces the pop: called, toast shown, route stays', (
    tester,
  ) async {
    // The master-detail shell swaps panes instead of popping — with a
    // callback wired, the form must leave navigation entirely to it.
    var saved = 0;
    final source = FakeSource(components: formWith());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const ValueKey('open'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ResourceFormScreen(
                    provider: providerFor(source),
                    onSaved: () => saved++,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.tap(find.byKey(const ValueKey('form.submit')));
    await tester.pumpAndSettle();

    expect(saved, 1);
    expect(
      find.byType(ResourceFormScreen),
      findsOneWidget,
      reason: 'not popped',
    );
    expect(find.text(const FilamentStrings().saved), findsOneWidget);
  });
}
