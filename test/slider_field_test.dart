import 'package:filament_mobile/form/client_validator.dart' as validator;
import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/form/fields/field_widgets.dart';
import 'package:filament_mobile/form/form_values.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsed through the real [SchemaComponent.fromJson], the same discipline
/// every field test in this suite follows.
SchemaComponent sliderField(
  String name, {
  num min = 0,
  num max = 100,
  num? step,
  bool multiple = false,
  Object? defaultValue,
  Map<String, dynamic>? rules,
}) => SchemaComponent.fromJson({
  'type': 'slider',
  'name': name,
  'label': name,
  if (defaultValue != null) 'default': defaultValue,
  if (rules != null) 'rules': rules,
  'config': {
    'min': min,
    'max': max,
    if (step != null) 'step': step,
    'multiple': multiple,
  },
}, 'form[0]');

/// The `StatefulBuilder` harness, same as radio_field_test.dart's — a drag
/// must visibly move the thumb, not only report into a void.
Widget sliderHarness({
  required SchemaComponent component,
  Object? value,
  bool enabled = true,
  String? error,
  ValueChanged<Object?>? onChanged,
}) {
  var current = value;
  return MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => FieldRegistry.defaults().build(
          context,
          component,
          FieldState(
            value: current,
            onChanged: (v) {
              setState(() => current = v);
              onChanged?.call(v);
            },
            enabled: enabled,
            error: error,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('single renders a Material Slider honouring min, max and step', (
    tester,
  ) async {
    await tester.pumpWidget(
      sliderHarness(
        component: sliderField('rating', min: 0, max: 10, step: 1),
        value: 5,
      ),
    );

    expect(find.byType(SliderFieldWidget), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 0);
    expect(slider.max, 10);
    // 0..10 in steps of 1 is ten gaps.
    expect(slider.divisions, 10);
    expect(slider.value, 5);
  });

  testWidgets('a slider without a step has no divisions', (tester) async {
    await tester.pumpWidget(
      sliderHarness(component: sliderField('rating'), value: 50),
    );

    expect(tester.widget<Slider>(find.byType(Slider)).divisions, isNull);
  });

  testWidgets('a drag reports a value snapped to the step', (tester) async {
    Object? received;
    await tester.pumpWidget(
      sliderHarness(
        component: sliderField('rating', min: 0, max: 10, step: 1),
        value: 5,
        onChanged: (v) => received = v,
      ),
    );

    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pump();

    expect(received, isA<num>());
    final value = (received! as num).toDouble();
    expect(value, greaterThan(5));
    expect(value, lessThanOrEqualTo(10));
    expect(
      value % 1,
      0,
      reason: 'a stepped slider snaps every reported value to the step',
    );
  });

  testWidgets('multiple renders a RangeSlider seeded from the two-element '
      'value', (tester) async {
    await tester.pumpWidget(
      sliderHarness(
        component: sliderField(
          'price_range',
          max: 100,
          step: 5,
          multiple: true,
        ),
        value: const [20, 40],
      ),
    );

    final slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
    expect(slider.values, const RangeValues(20, 40));
    expect(slider.min, 0);
    expect(slider.max, 100);
    expect(slider.divisions, 20);
  });

  testWidgets('a range drag reports a two-element List', (tester) async {
    Object? received;
    await tester.pumpWidget(
      sliderHarness(
        component: sliderField('price_range', multiple: true),
        value: const [20, 40],
        onChanged: (v) => received = v,
      ),
    );

    await tester.drag(find.byType(RangeSlider), const Offset(30, 0));
    await tester.pump();

    expect(received, isA<List>());
    expect((received! as List), hasLength(2));
  });

  testWidgets('enabled == false renders both shapes inert', (tester) async {
    Object? received;
    await tester.pumpWidget(
      sliderHarness(
        component: sliderField('rating', min: 0, max: 10),
        value: 5,
        enabled: false,
        onChanged: (v) => received = v,
      ),
    );

    // The hard gate: the control's own onChanged is null, not just unwired.
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);

    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pump();

    expect(received, isNull);
  });

  testWidgets('a value outside the published bounds renders clamped rather '
      'than crashing', (tester) async {
    // Slider *asserts* when its value lies outside [min, max] — the same red-
    // screen class DropdownButtonFormField already bit this suite with. A
    // stored record value can outlive a later narrowing of the bounds.
    await tester.pumpWidget(
      sliderHarness(
        component: sliderField('rating', min: 0, max: 10),
        value: 99,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 10);
  });

  testWidgets('a scalar value under multiple: true renders rather than '
      'crashing', (tester) async {
    // The documented server weakness: a range slider with no array default
    // publishes multiple: false on /schema, and /state may re-answer true
    // while the form value is still a scalar. Render benign; the value in
    // FormValues is untouched until the user drags.
    await tester.pumpWidget(
      sliderHarness(
        component: sliderField('price_range', multiple: true),
        value: 5,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(RangeSlider), findsOneWidget);
  });

  testWidgets('shows the field error', (tester) async {
    await tester.pumpWidget(
      sliderHarness(
        component: sliderField('rating'),
        value: 5,
        error: 'Out of range.',
      ),
    );

    expect(find.text('Out of range.'), findsOneWidget);
  });

  group('validation goes through the published rules, not a duplicate', () {
    final component = sliderField(
      'rating',
      min: 0,
      max: 10,
      rules: const {'required': true, 'numeric': true, 'min': 0, 'max': 10},
    );

    test('required fires on an empty value', () {
      final errors = validator.validate([
        component,
      ], FormValues.initial([component]));

      expect(errors.keys, ['rating']);
    });

    test('min/max fire on an out-of-bounds number', () {
      final tooLow = validator.validate([
        component,
      ], FormValues.initial([component]).set('rating', -1));
      final tooHigh = validator.validate([
        component,
      ], FormValues.initial([component]).set('rating', 11));

      expect(tooLow.keys, ['rating']);
      expect(tooHigh.keys, ['rating']);
    });

    test('an in-bounds value passes', () {
      final errors = validator.validate([
        component,
      ], FormValues.initial([component]).set('rating', 7));

      expect(errors, isEmpty);
    });
  });
}
