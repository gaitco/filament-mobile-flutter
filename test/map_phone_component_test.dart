import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses map hints and numeric-string default coordinates', () {
    final component =
        SchemaComponent.fromJson(const {
              'type': 'map_point',
              'name': 'location',
              'label': 'Location',
              'config': {
                'draggable': false,
                'clickable': true,
                'showMarker': false,
                'zoom': '12',
                'minZoom': 3,
                'maxZoom': 19,
                'tilesUrl': 'https://tiles.example/{z}/{x}/{y}.png',
                'attribution': 'Map data',
                'default': {'lat': '30.0444', 'lng': '31.2357'},
              },
            }, 'form[0]')
            as MapPointComponent;

    expect(component.draggable, isFalse);
    expect(component.clickable, isTrue);
    expect(component.showMarker, isFalse);
    expect(component.zoom, 12);
    expect(component.minZoom, 3);
    expect(component.maxZoom, 19);
    expect(component.attribution, 'Map data');
    expect(
      component.defaultValue,
      const MapPointValue(lat: 30.0444, lng: 31.2357),
    );
  });

  test('parses the map entry through the same typed value model', () {
    final component = SchemaComponent.fromJson(const {
      'type': 'map_point_entry',
      'name': 'location',
      'config': {'zoom': 10},
    }, 'infolist[0]');

    expect(component, isA<MapPointComponent>());
    expect((component as MapPointComponent).isEntry, isTrue);
  });

  test('rejects a map default without two numeric coordinates', () {
    expect(
      () => SchemaComponent.fromJson(const {
        'type': 'map_point',
        'name': 'location',
        'config': {
          'default': {'lat': 'north', 'lng': 31},
        },
      }, 'form[0]'),
      throwsA(isA<SchemaFormatException>()),
    );
  });

  test('parses phone format and country hints without changing the value', () {
    final component =
        SchemaComponent.fromJson(const {
              'type': 'phone',
              'name': 'phone',
              'default': '+20 2 2411 8610',
              'config': {
                'format': 'national',
                'countryPath': 'phone_country',
                'defaultCountry': 'EG',
                'onlyCountries': ['EG', 'SA'],
                'excludeCountries': ['US'],
              },
            }, 'form[0]')
            as PhoneComponent;

    expect(component.format, PhoneFormat.national);
    expect(component.countryPath, 'phone_country');
    expect(component.defaultCountry, 'EG');
    expect(component.onlyCountries, ['EG', 'SA']);
    expect(component.excludeCountries, ['US']);
    expect(component.defaultValue, '+20 2 2411 8610');
  });

  testWidgets('phone uses the phone keyboard and round-trips text verbatim', (
    tester,
  ) async {
    Object? changed;
    final component =
        SchemaComponent.fromJson(const {
              'type': 'phone',
              'name': 'phone',
              'label': 'Phone',
            }, 'form[0]')
            as PhoneComponent;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhoneFieldWidget(
            component: component,
            state: FieldState(
              value: '+20 (2) 2411-8610',
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).keyboardType,
      TextInputType.phone,
    );
    await tester.enterText(find.byType(TextField), '+20 2 0000 0000 ext 7');
    expect(changed, '+20 2 0000 0000 ext 7');
  });

  testWidgets('phone displays a server 422 error on the field', (tester) async {
    final component =
        SchemaComponent.fromJson(const {
              'type': 'phone',
              'name': 'phone',
              'label': 'Phone',
            }, 'form[0]')
            as PhoneComponent;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhoneFieldWidget(
            component: component,
            state: FieldState(
              value: 'bad',
              error: 'The phone field must be a valid phone number.',
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('The phone field must be a valid phone number.'),
      findsOneWidget,
    );
  });

  testWidgets('an unregistered map field renders an honest fallback', (
    tester,
  ) async {
    final component = SchemaComponent.fromJson(const {
      'type': 'map_point',
      'name': 'location',
      'label': 'Location',
    }, 'form[0]');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FieldRegistry.defaults().build(
              context,
              component,
              FieldState(value: null, onChanged: (_) {}),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Renderer not registered: map_point'), findsOneWidget);
  });
}
