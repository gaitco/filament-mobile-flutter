// P18 Task 6, Step 1: ReorderConfig parsing — `resource.reorder` is present
// if and only if the server's `/schema` response carried it, and a malformed
// value degrades to null rather than throwing (see ReorderConfig.fromJson's
// doc for why this is lenient, unlike most of this schema layer).

import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:flutter_test/flutter_test.dart';

ResourceSchema _resource(Map<String, dynamic> extra) =>
    ResourceSchema.fromJson({
      'key': 'slides',
      'labels': {'singular': 'Slide', 'plural': 'Slides'},
      ...extra,
    }, 'r');

void main() {
  group('ReorderConfig.fromJson', () {
    test('parses a well-formed {column, direction}', () {
      final config = ReorderConfig.fromJson(const {
        'column': 'position',
        'direction': 'asc',
      });

      expect(config, const ReorderConfig(column: 'position', direction: 'asc'));
    });

    test('defaults direction to asc when absent or not desc', () {
      expect(
        ReorderConfig.fromJson(const {'column': 'position'})?.direction,
        'asc',
      );
      expect(
        ReorderConfig.fromJson(const {
          'column': 'position',
          'direction': 'sideways',
        })?.direction,
        'asc',
      );
    });

    test('reads desc verbatim', () {
      expect(
        ReorderConfig.fromJson(const {
          'column': 'position',
          'direction': 'desc',
        })?.direction,
        'desc',
      );
    });

    test('null for absent, non-map, or a map missing a string column', () {
      expect(ReorderConfig.fromJson(null), isNull);
      expect(ReorderConfig.fromJson('nope'), isNull);
      expect(ReorderConfig.fromJson(const []), isNull);
      expect(ReorderConfig.fromJson(const <String, dynamic>{}), isNull);
      expect(ReorderConfig.fromJson(const {'column': 5}), isNull);
      expect(ReorderConfig.fromJson(const {'column': ''}), isNull);
    });
  });

  group('ResourceSchema.fromJson reorder', () {
    test('absent reorder key leaves resource.reorder null', () {
      expect(_resource(const {}).reorder, isNull);
    });

    test('a well-formed reorder key parses onto resource.reorder', () {
      final resource = _resource(const {
        'reorder': {'column': 'position', 'direction': 'asc'},
      });

      expect(
        resource.reorder,
        const ReorderConfig(column: 'position', direction: 'asc'),
      );
    });

    test('a malformed reorder key degrades to null, not a thrown error', () {
      expect(_resource(const {'reorder': 'nope'}).reorder, isNull);
      expect(_resource(const {'reorder': <String, dynamic>{}}).reorder, isNull);
    });
  });
}
