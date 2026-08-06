import 'package:filament_mobile/data/resource_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _literalKeyFirst();
  group('ResourceRecord', () {
    test('reads a flat attribute', () {
      final record = ResourceRecord.fromJson(const {
        'id': 7,
        'name': 'أحمد',
      }, 'id');

      expect(record.id, 7);
      expect(record.get<String>('name'), 'أحمد');
    });

    test('resolves a dotted path into the nested object the server sends', () {
      final record = ResourceRecord.fromJson(const {
        'id': 1,
        'company': {
          'name': 'جيت',
          'owner': {'email': 'a@b.c'},
        },
      }, 'id');

      expect(record.get<String>('company.name'), 'جيت');
      expect(record.get<String>('company.owner.email'), 'a@b.c');
    });

    test('a null anywhere along a dotted path yields null, never an error', () {
      final record = ResourceRecord.fromJson(const {
        'id': 1,
        'company': null,
      }, 'id');

      expect(record.get<String>('company.name'), isNull);
      expect(record.get<String>('missing.deeply.nested'), isNull);
    });

    test('a wrong-typed read yields null rather than throwing', () {
      final record = ResourceRecord.fromJson(const {'id': 1, 'count': 5}, 'id');

      expect(record.get<String>('count'), isNull);
      expect(record.get<int>('count'), 5);
    });

    test('honours a non-id record key', () {
      final record = ResourceRecord.fromJson(const {
        'uuid': 'abc-123',
        'name': 'x',
      }, 'uuid');

      expect(record.id, 'abc-123');
    });

    test('throws when the record key is absent', () {
      expect(
        () => ResourceRecord.fromJson(const {'name': 'x'}, 'id'),
        throwsA(isA<ArgumentError>()),
      );
    });

    group('permissions', () {
      test('are empty for a list record, which does not carry them', () {
        final record = ResourceRecord.fromJson(const {'id': 1}, 'id');

        expect(record.permissions, isEmpty);
        expect(record.can('delete'), isFalse);
      });

      test('come from the record endpoint and deny by default', () {
        final record = ResourceRecord.fromJson(
          const {'id': 1},
          'id',
          permissions: const {'view': true, 'update': false},
        );

        expect(record.can('view'), isTrue);
        expect(record.can('update'), isFalse);
        // Absent means denied — never assume an unlisted ability is allowed.
        expect(record.can('delete'), isFalse);
      });
    });

    test('equality is by id', () {
      final a = ResourceRecord.fromJson(const {'id': 1, 'name': 'a'}, 'id');
      final b = ResourceRecord.fromJson(const {'id': 1, 'name': 'b'}, 'id');

      expect(a, b);
    });

    test('fake() produces a record shaped for the skeleton card', () {
      final fake = ResourceRecord.fake(0);

      expect(fake.get<String>('title'), isNotEmpty);
      expect(fake.get<String>('subtitle'), isNotEmpty);
      expect(fake.get<String>('meta'), isNotEmpty);
    });
  });
}

void _literalKeyFirst() {
  group('a literal dotted key wins over a traversal', () {
    test('reads a form field the server wrote under its literal key', () {
      // The server writes FORM paths flat — `caption.en` is its own key, not a
      // nesting — because an infolist entry named `caption` and a form field
      // named `caption.en` are different things sharing one base key.
      const record = ResourceRecord(
        id: 1,
        attributes: {'caption': 'the infolist scalar', 'caption.en': 'English'},
      );

      expect(record.get<String>('caption.en'), 'English');
    });

    test('still traverses when no literal key exists', () {
      // A card's `company.name` has no literal key and must keep working, or
      // every card in the panel breaks.
      const record = ResourceRecord(
        id: 1,
        attributes: {
          'company': {'name': 'Acme'},
        },
      );

      expect(record.get<String>('company.name'), 'Acme');
    });

    test('the literal key wins even when a traversal would also succeed', () {
      // The collision exactly. Both are present and they mean different
      // things; the literal is the form's answer and must not lose.
      const record = ResourceRecord(
        id: 1,
        attributes: {
          'caption': {'en': 'nested'},
          'caption.en': 'literal',
        },
      );

      expect(record.get<String>('caption.en'), 'literal');
    });
  });
}
