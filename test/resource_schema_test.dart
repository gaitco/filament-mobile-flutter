import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

ResourceSchema resourceFrom(Map<String, dynamic> json) =>
    ResourceSchema.fromJson({
      ...json,
      'labels': json['labels'] ?? {'singular': 'a', 'plural': 'b'},
    }, 'r');

void main() {
  group('ResourceSchema', () {
    test('parses a full resource', () {
      final resource = ResourceSchema.fromJson(const {
        'key': 'users',
        'labels': {
          'singular': 'مستخدم',
          'plural': 'المستخدمون',
          'icon': 'users',
        },
        'permissions': {'viewAny': true, 'view': true, 'create': true},
        'recordKey': 'uuid',
        'card': {
          'title': {'field': 'name'},
        },
        'search': {'enabled': true, 'placeholder': 'ابحث'},
        'sorts': [
          {
            'key': 'created_at',
            'label': 'الأحدث',
            'direction': 'desc',
            'default': true,
          },
          {'key': 'name', 'label': 'الاسم'},
        ],
        'filters': [
          {'type': 'select', 'name': 'status'},
        ],
        'form': [
          {'type': 'text', 'name': 'name'},
        ],
        'infolist': [
          {'type': 'text_entry', 'name': 'name'},
        ],
      }, 'resources[0]');

      expect(resource.key, 'users');
      expect(resource.labels.plural, 'المستخدمون');
      expect(resource.permissions.create, isTrue);
      expect(resource.permissions.delete, isFalse);
      expect(resource.recordKey, 'uuid');
      expect(resource.card.titleField, 'name');
      expect(resource.search.enabled, isTrue);
      expect(resource.search.placeholder, 'ابحث');
      expect(resource.sorts, hasLength(2));
      expect(resource.filters.single, isA<SelectComponent>());
      expect(resource.form.single, isA<TextComponent>());
      expect(resource.infolist.single, isA<EntryComponent>());
    });

    test('defaults recordKey to id and search to disabled', () {
      final resource = ResourceSchema.fromJson(const {
        'key': 'posts',
        'labels': {'singular': 'مقال', 'plural': 'المقالات'},
      }, 'resources[0]');

      expect(resource.recordKey, 'id');
      expect(resource.search.enabled, isFalse);
      expect(resource.card, isNotNull);
      expect(resource.form, isEmpty);
    });

    test(
      'defaultSort returns the flagged sort, or null when none is flagged',
      () {
        final withDefault = ResourceSchema.fromJson(const {
          'key': 'users',
          'labels': {'singular': 'a', 'plural': 'b'},
          'sorts': [
            {'key': 'name', 'label': 'الاسم'},
            {'key': 'created_at', 'label': 'الأحدث', 'default': true},
          ],
        }, 'resources[0]');
        expect(withDefault.defaultSort!.key, 'created_at');

        final withoutDefault = ResourceSchema.fromJson(const {
          'key': 'users',
          'labels': {'singular': 'a', 'plural': 'b'},
          'sorts': [
            {'key': 'name', 'label': 'الاسم'},
          ],
        }, 'resources[0]');
        expect(withoutDefault.defaultSort, isNull);
      },
    );

    test('ResourceSort defaults direction to asc and default to false', () {
      final resource = ResourceSchema.fromJson(const {
        'key': 'users',
        'labels': {'singular': 'a', 'plural': 'b'},
        'sorts': [
          {'key': 'name', 'label': 'الاسم'},
        ],
      }, 'resources[0]');

      expect(resource.sorts.single.direction, 'asc');
      expect(resource.sorts.single.isDefault, isFalse);
    });

    test('ResourceSort accepts asc and desc and rejects anything else', () {
      String directionOf(String raw) => ResourceSchema.fromJson({
        'key': 'users',
        'labels': const {'singular': 'a', 'plural': 'b'},
        'sorts': [
          {'key': 'name', 'label': 'الاسم', 'direction': raw},
        ],
      }, 'resources[0]').sorts.single.direction;

      expect(directionOf('asc'), 'asc');
      expect(directionOf('desc'), 'desc');
      expect(
        () => directionOf('descending'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'resources[0].sorts[0].direction',
          ),
        ),
      );
    });

    group('a sub-object present with the wrong type is a violation', () {
      for (final key in ['permissions', 'card', 'search']) {
        test('$key throws when it is not an object', () {
          expect(
            () => ResourceSchema.fromJson({
              'key': 'users',
              'labels': const {'singular': 'a', 'plural': 'b'},
              key: key == 'permissions' ? 5 : 'not-an-object',
            }, 'resources[0]'),
            throwsA(
              isA<SchemaFormatException>().having(
                (e) => e.path,
                'path',
                'resources[0].$key',
              ),
            ),
          );
        });
      }

      test('while an absent one still takes its default', () {
        final resource = ResourceSchema.fromJson(const {
          'key': 'users',
          'labels': {'singular': 'a', 'plural': 'b'},
        }, 'resources[0]');

        expect(resource.permissions.viewAny, isFalse);
        expect(resource.card, const CardLayout.empty());
        expect(resource.search.enabled, isFalse);
      });
    });

    test('fake() produces a skeleton-shaped resource', () {
      final fake = ResourceSchema.fake();

      expect(fake.key, isNotEmpty);
      expect(fake.labels.singular, isNotEmpty);
      expect(fake.card.titleField, isNotNull);
      expect(fake.card.subtitleField, isNotNull);
      expect(fake.form, isNotEmpty);
    });

    test('equality is by key', () {
      final a = ResourceSchema.fromJson(const {
        'key': 'users',
        'labels': {'singular': 'a', 'plural': 'b'},
      }, 'r');
      final b = ResourceSchema.fromJson(const {
        'key': 'users',
        'labels': {'singular': 'x', 'plural': 'y'},
      }, 'r');

      expect(a, b);
    });

    test('parses group, null when absent', () {
      expect(resourceFrom({'key': 'a', 'group': 'Content'}).group, 'Content');
      expect(resourceFrom({'key': 'a'}).group, isNull);
    });

    test('an empty group reads as null, not an empty group name', () {
      // An empty string would render as a group with a blank heading.
      expect(resourceFrom({'key': 'a', 'group': ''}).group, isNull);
    });

    test('group participates in equality', () {
      // Omitting it from props makes two differing resources compare equal,
      // silently defeating any rebuild that depends on the difference.
      expect(
        resourceFrom({'key': 'a', 'group': 'X'}),
        isNot(resourceFrom({'key': 'a'})),
      );
    });
  });
}
