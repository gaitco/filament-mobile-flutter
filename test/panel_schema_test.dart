import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> panelJson({int version = 1}) => {
  'version': version,
  'panel': {
    'id': 'admin',
    'title': 'لوحة التحكم',
    'navigation': [
      {
        'group': 'الإدارة',
        'resources': ['users', 'roles'],
      },
    ],
  },
  'resources': [
    {
      'key': 'users',
      'labels': {'singular': 'مستخدم', 'plural': 'المستخدمون'},
    },
    {
      'key': 'roles',
      'labels': {'singular': 'دور', 'plural': 'الأدوار'},
    },
  ],
};

void main() {
  group('PanelSchema', () {
    test('parses the panel and its resources', () {
      final panel = PanelSchema.fromJson(panelJson());

      expect(panel.version, 1);
      expect(panel.id, 'admin');
      expect(panel.title, 'لوحة التحكم');
      expect(panel.navigation.single.group, 'الإدارة');
      expect(panel.navigation.single.resources, ['users', 'roles']);
      expect(panel.resources, hasLength(2));
    });

    test('resource() looks a resource up by key', () {
      final panel = PanelSchema.fromJson(panelJson());

      expect(panel.resource('users')!.labels.singular, 'مستخدم');
      expect(panel.resource('missing'), isNull);
    });

    test('rejects a newer contract version rather than half-parsing it', () {
      expect(
        () => PanelSchema.fromJson(panelJson(version: 2)),
        throwsA(
          isA<UnsupportedSchemaVersionException>()
              .having((e) => e.found, 'found', 2)
              .having((e) => e.supported, 'supported', 1),
        ),
      );
    });

    test('a missing version is a contract violation, not version 1', () {
      final json = panelJson()..remove('version');
      expect(() => PanelSchema.fromJson(json), throwsA(isA<Exception>()));
    });

    test('root-level keys report a path that exists in the document', () {
      String pathOf(String missingKey) {
        final json = panelJson()..remove(missingKey);
        try {
          PanelSchema.fromJson(json);
        } on SchemaFormatException catch (error) {
          return error.path;
        }
        return 'did not throw';
      }

      expect(pathOf('version'), 'version');
      expect(pathOf('panel'), 'panel');
    });

    test('a non-string navigation entry throws with its index', () {
      final json = panelJson();
      (json['panel'] as Map<String, dynamic>)['navigation'] = [
        {
          'group': 'الإدارة',
          'resources': ['users', 7],
        },
      ];

      expect(
        () => PanelSchema.fromJson(json),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'panel.navigation[0].resources[1]',
          ),
        ),
      );
    });

    test('composes a path through every level of nesting', () {
      final json = panelJson();
      json['resources'] = [
        {
          'key': 'users',
          'labels': {'singular': 'مستخدم', 'plural': 'المستخدمون'},
          'form': [
            {'type': 'text', 'name': 'name'},
            {
              'type': 'section',
              'children': [
                {
                  'type': 'grid',
                  'children': [
                    {'type': 'text', 'name': 'a'},
                    {
                      'type': 'select',
                      'name': 'role_id',
                      'config': {
                        'options': [
                          {'value': 1, 'label': 'مدير'},
                          {'value': 2},
                        ],
                      },
                    },
                  ],
                },
              ],
            },
          ],
        },
      ];

      expect(
        () => PanelSchema.fromJson(json),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'resources[0].form[1].children[0].children[1]'
                '.config.options[1].label',
          ),
        ),
      );
    });

    test('navigation is optional', () {
      final json = panelJson();
      (json['panel'] as Map<String, dynamic>).remove('navigation');

      expect(PanelSchema.fromJson(json).navigation, isEmpty);
    });

    test('reports the path of a malformed resource', () {
      final json = panelJson();
      json['resources'] = [
        {'labels': <String, dynamic>{}},
      ];

      expect(
        () => PanelSchema.fromJson(json),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'resources[0].key',
          ),
        ),
      );
    });

    test('a non-object resource element throws with its index, not a '
        'TypeError', () {
      final json = panelJson();
      json['resources'] = [1];

      expect(
        () => PanelSchema.fromJson(json),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'resources[0]',
          ),
        ),
      );
    });

    test('a non-list resources value throws', () {
      final json = panelJson();
      json['resources'] = 'nope';

      expect(
        () => PanelSchema.fromJson(json),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'resources',
          ),
        ),
      );
    });

    group('direction and locale', () {
      test('parses a real direction and locale off the panel block', () {
        final json = panelJson();
        (json['panel'] as Map<String, dynamic>)['direction'] = 'rtl';
        (json['panel'] as Map<String, dynamic>)['locale'] = 'ar';

        final panel = PanelSchema.fromJson(json);

        expect(panel.direction, PanelDirection.rtl);
        expect(panel.locale, 'ar');
      });

      test('an absent direction reads as ltr — a server predating P6f, not a '
          'malformed contract', () {
        final json = panelJson();
        expect(
          (json['panel'] as Map<String, dynamic>).containsKey('direction'),
          isFalse,
        );

        expect(PanelSchema.fromJson(json).direction, PanelDirection.ltr);
      });

      test('an unrecognised direction reads as ltr — the client does not '
          'trust that the server normalised it', () {
        final json = panelJson();
        (json['panel'] as Map<String, dynamic>)['direction'] = 'sideways';

        expect(PanelSchema.fromJson(json).direction, PanelDirection.ltr);
      });

      test('every resource carries the panel\'s direction, not just the first '
          '— the fixture has two resources so a bug that populated only the '
          'first fails here', () {
        final json = panelJson();
        (json['panel'] as Map<String, dynamic>)['direction'] = 'rtl';
        expect(json['resources'], hasLength(greaterThan(1)));

        final panel = PanelSchema.fromJson(json);

        expect(panel.resources, hasLength(greaterThan(1)));
        for (final resource in panel.resources) {
          expect(
            resource.direction,
            PanelDirection.rtl,
            reason: '${resource.key} did not inherit the panel direction',
          );
        }
      });
    });
  });
}
