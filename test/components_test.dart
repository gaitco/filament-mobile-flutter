import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

T parse<T extends SchemaComponent>(Map<String, dynamic> json) =>
    SchemaComponent.fromJson(json, 'form[0]') as T;

void main() {
  group('NumberComponent', () {
    test('parses default, prefix, suffix and numeric bounds', () {
      final component = parse<NumberComponent>(const {
        'type': 'number',
        'name': 'price',
        'default': 10,
        'config': {'prefix': 'ج.م', 'suffix': null},
        'rules': {'min': 0, 'max': 9999},
      });

      expect(component.defaultValue, 10);
      expect(component.prefix, 'ج.م');
      expect(component.suffix, isNull);
      expect(component.rules.min, 0);
      expect(component.rules.max, 9999);
    });
  });

  group('SelectComponent', () {
    test('parses inline options', () {
      final component = parse<SelectComponent>(const {
        'type': 'select',
        'name': 'role_id',
        'config': {
          'options': [
            {'value': 1, 'label': 'مدير'},
            {'value': 2, 'label': 'محرر'},
          ],
          'searchable': true,
        },
      });

      expect(component.options, hasLength(2));
      expect(component.options.first.value, 1);
      expect(component.options.first.label, 'مدير');
      expect(component.searchable, isTrue);
      expect(component.multiple, isFalse);
      expect(component.optionsUrl, isNull);
    });

    test('parses a remote options url with no inline options', () {
      final component = parse<SelectComponent>(const {
        'type': 'select',
        'name': 'city_id',
        'config': {'optionsUrl': '/api/mobile-panel/users/options/city_id'},
      });

      expect(component.options, isEmpty);
      expect(component.optionsUrl, '/api/mobile-panel/users/options/city_id');
    });

    test('multiselect sets multiple', () {
      final component = parse<SelectComponent>(const {
        'type': 'multiselect',
        'name': 'tags',
      });
      expect(component.multiple, isTrue);
    });

    test('config.multiple can force multiple on a plain select', () {
      final component = parse<SelectComponent>(const {
        'type': 'select',
        'name': 'tags',
        'config': {'multiple': true},
      });
      expect(component.multiple, isTrue);
    });
  });

  group('BooleanComponent', () {
    test('maps toggle and checkbox onto a kind', () {
      expect(
        parse<BooleanComponent>(const {'type': 'toggle', 'name': 'a'}).kind,
        BooleanKind.toggle,
      );
      expect(
        parse<BooleanComponent>(const {'type': 'checkbox', 'name': 'a'}).kind,
        BooleanKind.checkbox,
      );
    });

    test('defaults to false when no default is given', () {
      expect(
        parse<BooleanComponent>(const {
          'type': 'toggle',
          'name': 'a',
        }).defaultValue,
        isFalse,
      );
    });
  });

  group('FileComponent', () {
    test('parses a read-only file field', () {
      final component = parse<FileComponent>(const {
        'type': 'file',
        'name': 'avatar',
        'label': 'الصورة',
        'config': {'readOnly': true},
      });

      expect(component.name, 'avatar');
      expect(component.readOnly, isTrue);
    });

    test('defaults readOnly to true when config is absent', () {
      // P2 never emits a writable file field. Defaulting to false would let a
      // renderer offer an upload the server cannot accept.
      expect(
        parse<FileComponent>(const {'type': 'file', 'name': 'avatar'}).readOnly,
        isTrue,
      );
    });
  });

  group('DateComponent', () {
    test('maps date and datetime onto a kind', () {
      expect(
        parse<DateComponent>(const {'type': 'date', 'name': 'd'}).kind,
        DateKind.date,
      );
      expect(
        parse<DateComponent>(const {'type': 'datetime', 'name': 'd'}).kind,
        DateKind.datetime,
      );
    });

    test('parses ISO 8601 bounds', () {
      final component = parse<DateComponent>(const {
        'type': 'date',
        'name': 'born_at',
        'config': {'minDate': '1900-01-01', 'maxDate': '2026-08-02'},
      });

      expect(component.minDate, DateTime.utc(1900, 1, 1));
      expect(component.maxDate, DateTime.utc(2026, 8, 2));
    });

    test('an unparseable bound reads as absent rather than throwing', () {
      final component = parse<DateComponent>(const {
        'type': 'date',
        'name': 'born_at',
        'config': {'minDate': 'yesterday'},
      });

      expect(component.minDate, isNull);
    });
  });
}
