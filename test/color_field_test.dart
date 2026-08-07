import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/form/fields/field_widgets.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsed through the real [SchemaComponent.fromJson], like every other field
/// fixture in this suite — a hand-built [ColorComponent] could drift from
/// what the walker actually publishes (see `ColorTest.php`, which measures
/// it).
SchemaComponent colorField(String name, {String format = 'hex'}) =>
    SchemaComponent.fromJson({
      'type': 'color',
      'name': name,
      'label': name,
      'config': {'format': format},
    }, 'form[0]');

Widget colorHarness({
  required SchemaComponent component,
  Object? value,
  bool enabled = true,
  ValueChanged<Object?>? onChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => FieldRegistry.defaults().build(
          context,
          component,
          FieldState(
            value: value,
            onChanged: onChanged ?? (_) {},
            enabled: enabled,
          ),
        ),
      ),
    ),
  );
}

Color? swatchColor(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.byKey(const ValueKey('color.swatch')),
  );
  return (container.decoration as BoxDecoration).color;
}

void main() {
  testWidgets('the registry builds a color field', (tester) async {
    await tester.pumpWidget(colorHarness(component: colorField('brand')));

    expect(find.byType(ColorFieldWidget), findsOneWidget);
  });

  testWidgets('the raw text is reported unmodified, never converted', (
    tester,
  ) async {
    // The property this task exists to prove: an `rgb`-declared field must
    // get `rgb` back, byte for byte — never silently rewritten to an
    // equivalent hex string. Typing text that is only valid as `rgb` and
    // asserting the SAME string comes back is the test that would fail if
    // any conversion happened.
    Object? reported;
    await tester.pumpWidget(
      colorHarness(
        component: colorField('brand', format: 'rgb'),
        onChanged: (v) => reported = v,
      ),
    );

    await tester.enterText(find.byType(TextField), 'rgb(10, 20, 30)');

    expect(reported, 'rgb(10, 20, 30)');
  });

  testWidgets('an hsl field reports hsl text unchanged too', (tester) async {
    Object? reported;
    await tester.pumpWidget(
      colorHarness(
        component: colorField('brand', format: 'hsl'),
        onChanged: (v) => reported = v,
      ),
    );

    await tester.enterText(find.byType(TextField), 'hsl(200, 50%, 60%)');

    expect(reported, 'hsl(200, 50%, 60%)');
  });

  testWidgets('a valid hex value colours the swatch', (tester) async {
    await tester.pumpWidget(
      colorHarness(component: colorField('brand'), value: '#336699'),
    );

    expect(swatchColor(tester), const Color(0xFF336699));
  });

  testWidgets('a malformed value holds the swatch at its last valid colour', (
    tester,
  ) async {
    // The documented rule: never blank the swatch on a bad keystroke.
    await tester.pumpWidget(
      colorHarness(component: colorField('brand'), value: '#336699'),
    );
    expect(swatchColor(tester), const Color(0xFF336699));

    await tester.enterText(find.byType(TextField), '#33669');
    // Fix round 1, Finding 2: `enterText` fires `onChanged` synchronously,
    // but the `setState` it triggers is not flushed to a frame until this
    // pump — without it, `tester.widget<Container>` below reads the PREVIOUS
    // build and the assertion passes even against a widget that blanks the
    // swatch on every malformed keystroke.
    await tester.pump();

    expect(
      swatchColor(tester),
      const Color(0xFF336699),
      reason: 'a malformed edit must not blank or change the swatch',
    );
  });

  testWidgets('a field with no valid value yet shows an empty swatch', (
    tester,
  ) async {
    await tester.pumpWidget(colorHarness(component: colorField('brand')));

    expect(swatchColor(tester), isNull);
  });

  testWidgets('rgba drives the swatch alpha, not just rgb', (tester) async {
    await tester.pumpWidget(
      colorHarness(
        component: colorField('brand', format: 'rgba'),
        value: 'rgba(255, 0, 0, 0.5)',
      ),
    );

    // Constructed the same way ColorFieldWidget itself builds it, so the
    // comparison exercises the real value rather than a channel-by-channel
    // reading through deprecated Color accessors.
    expect(swatchColor(tester), Color.fromRGBO(255, 0, 0, 0.5));
  });

  testWidgets('hsl is converted for display through HSLColor, not by hand', (
    tester,
  ) async {
    await tester.pumpWidget(
      colorHarness(
        component: colorField('brand', format: 'hsl'),
        value: 'hsl(0, 100%, 50%)',
      ),
    );

    // Pure red.
    expect(swatchColor(tester), const Color(0xFFFF0000));
  });

  testWidgets('a disabled color field reports nothing', (tester) async {
    Object? reported;
    await tester.pumpWidget(
      colorHarness(
        component: colorField('brand'),
        enabled: false,
        onChanged: (v) => reported = v,
      ),
    );

    await tester.enterText(find.byType(TextField), '#336699');

    expect(reported, isNull);
  });

  testWidgets('the field error is shown', (tester) async {
    await tester.pumpWidget(
      colorHarness(component: colorField('brand'), value: 'not a color'),
    );

    // The widget itself never sets errorText from parsing — client_validator
    // does, through FieldState.error. This proves the field surfaces
    // whatever it is given.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FieldRegistry.defaults().build(
              context,
              colorField('brand'),
              const FieldState(
                value: 'not a color',
                onChanged: _ignore,
                error: 'Enter a valid color in the expected format',
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Enter a valid color in the expected format'),
      findsOneWidget,
    );
  });
}

void _ignore(Object? value) {}
