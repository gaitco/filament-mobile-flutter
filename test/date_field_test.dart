import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `DateFieldWidget`'s picker had no test of its own until P8 Task 2's fix
/// round. Task 1 made `minDate`/`maxDate` real, which turned a latent
/// `showDatePicker` assertion into a crash on the first tap of any field whose
/// range excludes today — the exact hazard Task 2 fixed on the time path and
/// left standing here.
SchemaComponent dateField(
  String name, {
  String? minDate,
  String? maxDate,
  String type = 'date',
}) => SchemaComponent.fromJson({
  'type': type,
  'name': name,
  'label': name,
  'config': {'minDate': minDate, 'maxDate': maxDate},
}, 'form[0]');

Widget dateHarness({required SchemaComponent component, Object? value}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FieldRegistry.defaults().build(
            context,
            component,
            FieldState(value: value, onChanged: (_) {}),
          ),
        ),
      ),
    );

Future<void> tapField(WidgetTester tester) async {
  await tester.tap(find.byType(InputDecorator).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a field whose range excludes today opens without crashing', (
    tester,
  ) async {
    // `->minDate(now()->addDay())` on a booking date is the ordinary Filament
    // idiom that produced this; 2099 is the same shape, pinned to a fixed
    // year so the test cannot pass or fail by wall clock.
    await tester.pumpWidget(
      dateHarness(
        component: dateField(
          'booked_for',
          minDate: '2099-01-01',
          maxDate: '2099-12-31',
        ),
      ),
    );

    await tapField(tester);

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('a stored value outside later-tightened bounds still opens', (
    tester,
  ) async {
    // The other direction, and a real migration case: a record saved before
    // the panel narrowed its bounds.
    await tester.pumpWidget(
      dateHarness(
        component: dateField(
          'booked_for',
          minDate: '2099-01-01',
          maxDate: '2099-12-31',
        ),
        value: '2020-05-05T00:00:00.000Z',
      ),
    );

    await tapField(tester);

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('contradictory bounds degrade to no bounds, not a crash', (
    tester,
  ) async {
    // `showDatePicker` asserts `lastDate` is not before `firstDate` too, so
    // clamping the initial date alone would not save this one. A client must
    // not be crashable by what a server sends.
    await tester.pumpWidget(
      dateHarness(
        component: dateField(
          'booked_for',
          minDate: '2099-12-31',
          maxDate: '2099-01-01',
        ),
      ),
    );

    await tapField(tester);

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  // The timezone half of the clamp, which the four tests above cannot see:
  // they put the initial date so far outside its bounds that instant-wise and
  // calendar-day comparison agree, so dropping all three `DateUtils.dateOnly`
  // calls leaves them green.
  //
  // `showDatePicker` compares its three dates **date-only** before asserting
  // (date_picker.dart:227-241), so the clamp has to as well. A bound arrives
  // as a UTC calendar date (`DateComponent._parseDate` reinterprets it so
  // deliberately); a stored value without an offset parses as a local instant.
  // West of UTC those two frames disagree about which day it is.
  //
  // **Only a negative UTC offset can express the difference** — measured, not
  // assumed. At or east of UTC a local calendar day can never be *behind* the
  // UTC day of the same instant, so both strategies give the same answer and
  // no fixture can distinguish them; the mutation leaves the suite green under
  // UTC and under +03:00. `.github/workflows/dart.yml` therefore pins the gate
  // to `TZ=Pacific/Niue` (−11:00), and this skips only on a developer machine
  // that is not west of UTC.
  testWidgets('a stored value west of UTC clamps on the calendar day, not the '
      'instant (skipped unless TZ is west of UTC — see dart.yml)', (
    tester,
  ) async {
    // One minute past midnight UTC on the bound's own day: *after* `minDate`
    // as an instant, but still the previous calendar day where the user is.
    final stored = DateTime.utc(
      2026,
      8,
      7,
    ).toLocal().add(const Duration(minutes: 1));

    // Guards the fixture itself: if the zone cannot express the case, this
    // fails loudly rather than asserting nothing.
    expect(
      stored.day,
      6,
      reason: 'the stored value must sit a calendar day behind the bound',
    );

    await tester.pumpWidget(
      dateHarness(
        component: dateField(
          'booked_for',
          minDate: '2026-08-07',
          maxDate: '2026-12-31',
        ),
        value: stored.toIso8601String(),
      ),
    );

    await tapField(tester);

    expect(
      tester
          .widget<DatePickerDialog>(find.byType(DatePickerDialog))
          .initialDate,
      DateTime(2026, 8, 7),
    );
  }, skip: !DateTime.now().timeZoneOffset.isNegative);

  testWidgets('an ordinary bounded field still opens on its stored value', (
    tester,
  ) async {
    // The assertion the three above cannot make: clamping everything to
    // `firstDate` would pass all of them.
    await tester.pumpWidget(
      dateHarness(
        component: dateField(
          'booked_for',
          minDate: '2099-01-01',
          maxDate: '2099-12-31',
        ),
        value: '2099-06-15T00:00:00.000Z',
      ),
    );

    await tapField(tester);

    expect(
      tester
          .widget<DatePickerDialog>(find.byType(DatePickerDialog))
          .initialDate,
      DateTime(2099, 6, 15),
    );
  });
}
