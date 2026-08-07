import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/form/fields/field_widgets.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsed through the real [SchemaComponent.fromJson], like every other field
/// fixture in this suite: a hand-built [DateComponent] could drift from what
/// the walker actually publishes (see `TimeTest.php`, which measures it).
SchemaComponent timeField(
  String name, {
  String? minDate,
  String? maxDate,
  bool seconds = false,
}) => SchemaComponent.fromJson({
  'type': 'time',
  'name': name,
  'label': name,
  'config': {'minDate': minDate, 'maxDate': maxDate, 'seconds': seconds},
}, 'form[0]');

/// [alwaysUse24Hour] overrides the clock format for the *field* only. The
/// binding-level `alwaysUse24HourFormatTestValue` set in `setUp` is what the
/// picker dialog reads (it is a separate route), but changing it mid-test does
/// not reach an already-latched MediaQuery — so a display-only test that needs
/// the other format overrides it here instead.
Widget timeHarness({
  required SchemaComponent component,
  Object? value,
  bool enabled = true,
  bool? alwaysUse24Hour,
  ValueChanged<Object?>? onChanged,
}) {
  var current = value;
  return MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) {
          final field = FieldRegistry.defaults().build(
            context,
            component,
            FieldState(
              value: current,
              onChanged: (v) {
                setState(() => current = v);
                onChanged?.call(v);
              },
              enabled: enabled,
            ),
          );

          if (alwaysUse24Hour == null) return field;
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(alwaysUse24HourFormat: alwaysUse24Hour),
            child: field,
          );
        },
      ),
    ),
  );
}

/// Drives the dialog's keyboard-entry mode so a test can pick a specific
/// time. The dial is coordinate-driven and unassertable; the input mode is
/// two text fields, which is how a clamp can be proven against a time the
/// user really chose rather than against the one the field opened on.
Future<void> pickTime(WidgetTester tester, String hour, String minute) async {
  await tester.tap(find.byType(InputDecorator).first);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byIcon(Icons.keyboard_outlined),
    ),
  );
  await tester.pumpAndSettle();

  // Scoped to the dialog: the field itself is a TextField too, and the route
  // below stays mounted while the dialog is up.
  final fields = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.first, hour);
  await tester.enterText(fields.last, minute);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // 12-hour entry keeps whichever AM/PM segment the dialog opened on, so
    // typing "10" would report 10:30 or 22:30 depending on the wall clock —
    // a test that passes or fails by time of day. 24-hour entry makes the
    // typed digits the whole value.
    TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .alwaysUse24HourFormatTestValue =
        true;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearAlwaysUse24HourTestValue();
  });

  testWidgets('the registry builds a time field, not a date one', (
    tester,
  ) async {
    // `time` parses onto the same DateComponent as `date`/`datetime`, so the
    // registry discriminates on kind — and a bare `DateComponent()` case
    // listed first would swallow it and put a calendar in front of a field
    // that has no date.
    await tester.pumpWidget(timeHarness(component: timeField('opens_at')));

    expect(find.byType(TimeFieldWidget), findsOneWidget);
    expect(find.byType(DateFieldWidget), findsNothing);
  });

  testWidgets('a time field reports HH:mm, not an ISO datetime', (
    tester,
  ) async {
    Object? reported;
    await tester.pumpWidget(
      timeHarness(
        component: timeField('opens_at'),
        onChanged: (v) => reported = v,
      ),
    );

    await pickTime(tester, '10', '30');

    // Not `toIso8601String()`: a TimePicker's own format is `H:i` (`H:i:s`
    // with seconds) — measured in vendor — and a bare time has no date to
    // invent.
    expect(reported, '10:30');
  });

  testWidgets('seconds are appended only when the picker offers them', (
    tester,
  ) async {
    Object? reported;
    await tester.pumpWidget(
      timeHarness(
        component: timeField('opens_at', seconds: true),
        onChanged: (v) => reported = v,
      ),
    );

    await pickTime(tester, '10', '30');

    expect(reported, '10:30:00');
  });

  testWidgets('a pick below the declared minimum is clamped to it', (
    tester,
  ) async {
    Object? reported;
    await tester.pumpWidget(
      timeHarness(
        component: timeField('opens_at', minDate: '09:00', maxDate: '17:00'),
        onChanged: (v) => reported = v,
      ),
    );

    await pickTime(tester, '8', '00');

    expect(reported, '09:00');
  });

  testWidgets('a pick above the declared maximum is clamped to it', (
    tester,
  ) async {
    Object? reported;
    await tester.pumpWidget(
      timeHarness(
        component: timeField('opens_at', minDate: '09:00', maxDate: '17:00'),
        onChanged: (v) => reported = v,
      ),
    );

    await pickTime(tester, '21', '45');

    expect(reported, '17:00');
  });

  testWidgets('a pick inside the bounds is left exactly as chosen', (
    tester,
  ) async {
    // The assertion the two clamp tests cannot make on their own: a clamp
    // that always returned a bound would pass both of them.
    Object? reported;
    await tester.pumpWidget(
      timeHarness(
        component: timeField('opens_at', minDate: '09:00', maxDate: '17:00'),
        onChanged: (v) => reported = v,
      ),
    );

    await pickTime(tester, '11', '15');

    expect(reported, '11:15');
  });

  testWidgets('an unbounded field keeps a time no bound could allow', (
    tester,
  ) async {
    Object? reported;
    await tester.pumpWidget(
      timeHarness(
        component: timeField('closes_at'),
        onChanged: (v) => reported = v,
      ),
    );

    await pickTime(tester, '23', '59');

    expect(reported, '23:59');
  });

  testWidgets('the stored value is displayed, not re-parsed as a date', (
    tester,
  ) async {
    await tester.pumpWidget(
      timeHarness(component: timeField('opens_at'), value: '14:05:00'),
    );

    // `DateTime.tryParse('14:05:00')` is null, so a date-shaped read would
    // show an empty field for a value the server really sent. And `14:05`,
    // not the raw `14:05:00`: the value is formatted through
    // MaterialLocalizations, not echoed.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '14:05',
    );
  });

  testWidgets('a datetime field honours the same 24-hour setting', (
    tester,
  ) async {
    // The sibling call site. `formatTimeOfDay` defaults to 12-hour and does
    // not consult MediaQuery, so fixing only the time field would leave a
    // 24-hour user reading "2:05 PM" on every datetime field.
    await tester.pumpWidget(
      timeHarness(
        component: SchemaComponent.fromJson(const {
          'type': 'datetime',
          'name': 'published_at',
          'label': 'Published',
        }, 'form[0]'),
        value: '2026-01-01T14:05:00',
      ),
    );

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      contains('14:05'),
    );
  });

  testWidgets('a 12-hour user still reads a 12-hour clock', (tester) async {
    // The other half of the formatTimeOfDay fix. Hardcoding the 24-hour
    // branch to `true` passed the whole suite before this test existed, so
    // the regression the fix prevents in this direction was invisible — the
    // one-sided-fixture trap this project has hit thirteen times.
    await tester.pumpWidget(
      timeHarness(
        component: timeField('opens_at'),
        value: '14:05:00',
        alwaysUse24Hour: false,
      ),
    );

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '2:05 PM',
    );
  });

  testWidgets('a stored second survives a pick that did not change it', (
    tester,
  ) async {
    // showTimePicker has no seconds concept, so a flat `:00` would rewrite
    // 14:05:30 to 14:05:00 on nothing but opening the picker and pressing OK
    // — data loss on a no-op interaction, with nothing to signal it.
    Object? reported;
    await tester.pumpWidget(
      timeHarness(
        component: timeField('opens_at', seconds: true),
        value: '14:05:30',
        onChanged: (v) => reported = v,
      ),
    );

    await tester.tap(find.byType(InputDecorator).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(reported, '14:05:30');
  });

  testWidgets('a genuinely new time starts its seconds at zero', (
    tester,
  ) async {
    // The assertion the test above cannot make on its own: simply echoing
    // the stored value back would pass it.
    Object? reported;
    await tester.pumpWidget(
      timeHarness(
        component: timeField('opens_at', seconds: true),
        value: '14:05:30',
        onChanged: (v) => reported = v,
      ),
    );

    await pickTime(tester, '16', '20');

    expect(reported, '16:20:00');
  });

  testWidgets('a bounded field explains the range it will clamp to', (
    tester,
  ) async {
    // The clamp substitutes a time the user did not choose. Visible is not
    // the same as explained.
    await tester.pumpWidget(
      timeHarness(
        component: timeField('opens_at', minDate: '09:00', maxDate: '17:00'),
      ),
    );

    expect(find.text('Between 09:00 and 17:00'), findsOneWidget);
  });

  testWidgets('the panel\'s own helper text wins over the range', (
    tester,
  ) async {
    await tester.pumpWidget(
      timeHarness(
        component: SchemaComponent.fromJson(const {
          'type': 'time',
          'name': 'opens_at',
          'label': 'Opens at',
          'helperText': 'Local time',
          'config': {'minDate': '09:00', 'maxDate': '17:00'},
        }, 'form[0]'),
      ),
    );

    expect(find.text('Local time'), findsOneWidget);
    expect(find.text('Between 09:00 and 17:00'), findsNothing);
  });

  testWidgets('an unbounded field gets no range line', (tester) async {
    await tester.pumpWidget(timeHarness(component: timeField('closes_at')));

    expect(find.textContaining('Between'), findsNothing);
    expect(find.textContaining('From'), findsNothing);
  });

  testWidgets('a field bounded on one side only says so', (tester) async {
    await tester.pumpWidget(
      timeHarness(component: timeField('opens_at', minDate: '09:00')),
    );

    expect(find.text('From 09:00'), findsOneWidget);
  });

  testWidgets('the picker opens inside the declared bounds', (tester) async {
    await tester.pumpWidget(
      timeHarness(
        component: timeField('opens_at', minDate: '09:00', maxDate: '17:00'),
      ),
    );

    await tester.tap(find.byType(InputDecorator).first);
    await tester.pumpAndSettle();

    // No stored value, so the field falls back to "now" — which in a test
    // runs at wall-clock time and is usually outside 09:00–17:00. Opening on
    // a time the field would immediately clamp is a bad first impression, so
    // the fallback is clamped too.
    final dialog = tester.widget<TimePickerDialog>(
      find.byType(TimePickerDialog),
    );
    final initial = dialog.initialTime;
    expect(
      initial.hour * 60 + initial.minute,
      allOf(greaterThanOrEqualTo(9 * 60), lessThanOrEqualTo(17 * 60)),
    );
  });

  testWidgets('a bound the client could not read is flagged in debug', (
    tester,
  ) async {
    // Not a shrug: the panel declared a bound this build cannot honour, so
    // the field will offer times the server rejects. Invisible in release —
    // same rule the unrenderable-entry placeholder follows — but a developer
    // meets it on the first run.
    await tester.pumpWidget(
      timeHarness(component: timeField('opens_at', minDate: 'half nine')),
    );

    expect(find.textContaining('minDate'), findsOneWidget);
  });

  testWidgets('a field with readable bounds carries no such flag', (
    tester,
  ) async {
    await tester.pumpWidget(
      timeHarness(component: timeField('opens_at', minDate: '09:00')),
    );

    expect(find.textContaining('minDate'), findsNothing);
  });

  testWidgets('a disabled time field does not open the picker', (tester) async {
    await tester.pumpWidget(
      timeHarness(component: timeField('opens_at'), enabled: false),
    );

    await tester.tap(find.byType(InputDecorator).first);
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsNothing);
  });
}
