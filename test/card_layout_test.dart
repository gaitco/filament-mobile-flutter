import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/json_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CardLayout', () {
    test('parses every slot', () {
      final card = CardLayout.fromJson(const {
        'title': {'field': 'name'},
        'subtitle': {'field': 'email'},
        'leading': {
          'type': 'image',
          'field': 'avatar_url',
          'fallback': 'initials',
        },
        'badges': [
          {
            'field': 'status',
            'colors': {'active': 'success', 'banned': 'danger'},
          },
        ],
        'meta': [
          {'field': 'created_at', 'format': 'date'},
        ],
      }, 'resources[0].card');

      expect(card.titleField, 'name');
      expect(card.subtitleField, 'email');
      expect(card.leading!.type, 'image');
      expect(card.leading!.field, 'avatar_url');
      expect(card.leading!.fallback, 'initials');
      expect(card.badges.single.field, 'status');
      expect(card.badges.single.colors['active'], 'success');
      expect(card.meta.single.field, 'created_at');
      expect(card.meta.single.format, 'date');
    });

    test('every slot is optional — a title-only card is valid', () {
      final card = CardLayout.fromJson(const {
        'title': {'field': 'name'},
      }, 'resources[0].card');

      expect(card.titleField, 'name');
      expect(card.subtitleField, isNull);
      expect(card.leading, isNull);
      expect(card.badges, isEmpty);
      expect(card.meta, isEmpty);
    });

    test('an empty card object parses to the empty layout', () {
      expect(CardLayout.fromJson(const {}, 'card'), const CardLayout.empty());
    });

    test('a badge without a field is a contract violation', () {
      expect(
        () => CardLayout.fromJson(const {
          'badges': [
            {'colors': <String, String>{}},
          ],
        }, 'card'),
        throwsA(isA<Exception>()),
      );
    });

    test('a meta entry without a field is a contract violation', () {
      expect(
        () => CardLayout.fromJson(const {
          'meta': [
            {'format': 'date'},
          ],
        }, 'card'),
        throwsA(isA<Exception>()),
      );
    });

    test('a leading without a type or field is a contract violation', () {
      expect(
        () => CardLayout.fromJson(const {
          'leading': {'fallback': 'initials'},
        }, 'card'),
        throwsA(isA<Exception>()),
      );
    });

    test('a leading type outside the closed set throws', () {
      CardLeading leadingOf(String type) => CardLayout.fromJson({
        'leading': {'type': type, 'field': 'avatar_url'},
      }, 'card').leading!;

      expect(leadingOf('image').type, 'image');
      expect(leadingOf('icon').type, 'icon');
      expect(
        () => leadingOf('avatar'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'card.leading.type',
          ),
        ),
      );
    });

    test('a present slot with no field throws, unlike an absent slot', () {
      expect(
        () => CardLayout.fromJson(const {
          'title': <String, dynamic>{},
        }, 'resources[0].card'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'resources[0].card.title.field',
          ),
        ),
      );

      // The asymmetry: an absent slot is still perfectly valid.
      expect(CardLayout.fromJson(const {}, 'card').titleField, isNull);
    });
  });
}
