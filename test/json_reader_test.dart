import 'package:filament_mobile/schema/json_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('req', () {
    test('returns the value when the type matches', () {
      expect(req<String>({'name': 'email'}, 'name', 'form[0]'), 'email');
    });

    test('throws with the JSON path when the key is missing', () {
      expect(
        () => req<String>(const {}, 'name', 'form[0]'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'form[0].name',
          ),
        ),
      );
    });

    test('throws when the type is wrong', () {
      expect(
        () => req<String>({'name': 7}, 'name', 'form[0]'),
        throwsA(isA<SchemaFormatException>()),
      );
    });
  });

  group('opt', () {
    test('returns null for a missing key', () {
      expect(opt<String>(const {}, 'label'), isNull);
    });

    test('returns null for a wrong type rather than throwing', () {
      expect(opt<String>({'label': 7}, 'label'), isNull);
    });
  });

  group('objects', () {
    test('returns an empty list for a missing key', () {
      expect(objects(const {}, 'form', 'resource'), isEmpty);
    });

    test('returns the maps for a list of objects', () {
      final result = objects(
        {
          'form': [
            {'type': 'text'},
          ],
        },
        'form',
        'resource',
      );
      expect(result, hasLength(1));
      expect(result.first['type'], 'text');
    });

    test('throws when an element is not an object', () {
      expect(
        () => objects(
          {
            'form': ['nope'],
          },
          'form',
          'resource',
        ),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'resource.form[0]',
          ),
        ),
      );
    });
  });

  group('stringMap', () {
    test('returns an empty map for a missing key', () {
      expect(stringMap(const {}, 'colors'), isEmpty);
    });

    test('keeps only string values', () {
      expect(
        stringMap({
          'colors': {'active': 'success', 'count': 3},
        }, 'colors'),
        {'active': 'success'},
      );
    });
  });
}
