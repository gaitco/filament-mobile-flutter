import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EntryComponent', () {
    test('parses a target off config, absent reads as plain text', () {
      final targeted =
          SchemaComponent.fromJson(const {
                'type': 'text_entry',
                'name': 'category.name',
                'config': {
                  'target': {'resource': 'categories', 'record': 'category.id'},
                },
              }, 'infolist[0]')
              as EntryComponent;
      expect(targeted.targetResource, 'categories');
      expect(targeted.targetRecordPath, 'category.id');

      final plain =
          SchemaComponent.fromJson(const {
                'type': 'text_entry',
                'name': 'name',
              }, 'infolist[0]')
              as EntryComponent;
      expect(plain.targetResource, isNull);
      expect(plain.targetRecordPath, isNull);
    });

    test('maps each entry type onto a kind', () {
      EntryKind kindOf(String type) =>
          (SchemaComponent.fromJson({'type': type, 'name': 'f'}, 'infolist[0]')
                  as EntryComponent)
              .kind;

      expect(kindOf('text_entry'), EntryKind.text);
      expect(kindOf('badge_entry'), EntryKind.badge);
      expect(kindOf('image_entry'), EntryKind.image);
      expect(kindOf('boolean_entry'), EntryKind.boolean);
      expect(kindOf('date_entry'), EntryKind.date);
    });

    test('parses badge colours', () {
      final entry =
          SchemaComponent.fromJson(const {
                'type': 'badge_entry',
                'name': 'status',
                'config': {
                  'colors': {'active': 'success', 'banned': 'danger'},
                },
              }, 'infolist[0]')
              as EntryComponent;

      expect(entry.colors, {'active': 'success', 'banned': 'danger'});
    });

    test('parses a date format and an image fallback', () {
      final dateEntry =
          SchemaComponent.fromJson(const {
                'type': 'date_entry',
                'name': 'created_at',
                'config': {'format': 'd MMMM y'},
              }, 'infolist[0]')
              as EntryComponent;
      expect(dateEntry.format, 'd MMMM y');

      final imageEntry =
          SchemaComponent.fromJson(const {
                'type': 'image_entry',
                'name': 'avatar_url',
                'config': {'fallback': 'initials'},
              }, 'infolist[1]')
              as EntryComponent;
      expect(imageEntry.fallback, 'initials');
    });

    test('defaults colours to empty and format and fallback to null', () {
      final entry =
          SchemaComponent.fromJson(const {
                'type': 'text_entry',
                'name': 'bio',
              }, 'infolist[0]')
              as EntryComponent;

      expect(entry.colors, isEmpty);
      expect(entry.format, isNull);
      expect(entry.fallback, isNull);
    });
  });
}
