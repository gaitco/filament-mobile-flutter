import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/resource_action.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/schema/validation_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

Map<String, dynamic> get _panelJson => {
  'version': 1,
  'panel': {'id': 'mobile', 'title': 'لوحة التحكم'},
  'resources': [
    {
      'key': 'banners',
      'labels': {'singular': 'لافتة', 'plural': 'اللافتات'},
      'recordKey': 'id',
    },
  ],
};

RestResourceDataSource sourceFor(FakeTransport transport) =>
    RestResourceDataSource(transport: transport);

/// One rule, every site that carries a nested JSON object: a key that is
/// *absent* keeps its default, but a key that is *present* holding something
/// other than an object is a contract violation and throws with its path.
///
/// These sites all used `opt<Map>` at first, which reads a malformed value as
/// absent. That silence is the failure mode: a `select` whose `config` is a
/// string became a required field with no options and no `optionsUrl` — one
/// nobody can fill and nothing reports.
void main() {
  Matcher throwsAtPath(String path) =>
      throwsA(isA<SchemaFormatException>().having((e) => e.path, 'path', path));

  group('config', () {
    test('a non-object config throws, per component type', () {
      for (final type in ['select', 'number', 'date', 'text_entry']) {
        expect(
          () => SchemaComponent.fromJson({
            'type': type,
            'name': 'f',
            'config': 'nope',
          }, 'form[0]'),
          throwsAtPath('form[0].config'),
          reason: '$type should reject a non-object config',
        );
      }
    });

    test('an absent config still defaults', () {
      for (final type in ['select', 'number', 'date', 'text_entry']) {
        expect(
          SchemaComponent.fromJson({'type': type, 'name': 'f'}, 'form[0]').name,
          'f',
          reason: '$type should parse without a config',
        );
      }
    });
  });

  group('ResourceAction.confirmation', () {
    test('a non-object confirmation throws rather than reading as absent', () {
      expect(
        () => ResourceAction.fromJson(const {
          'name': 'delete',
          'label': 'حذف',
          'confirmation': 'yes',
        }, 'resources[0].actions[0]'),
        throwsAtPath('resources[0].actions[0].confirmation'),
      );
    });

    test('an absent confirmation is still null', () {
      final action = ResourceAction.fromJson(const {
        'name': 'delete',
        'label': 'حذف',
        'requiresConfirmation': true,
      }, 'actions[0]');
      expect(action.requiresConfirmation, isTrue);
      expect(action.confirmation, isNull);
    });
  });

  group('CardLayout nested objects', () {
    test('a non-object leading throws', () {
      expect(
        () => CardLayout.fromJson(const {
          'leading': 'avatar_url',
        }, 'resources[0].card'),
        throwsAtPath('resources[0].card.leading'),
      );
    });

    test('a non-object title or subtitle slot throws', () {
      expect(
        () => CardLayout.fromJson(const {'title': 'name'}, 'card'),
        throwsAtPath('card.title'),
      );
      expect(
        () => CardLayout.fromJson(const {'subtitle': 42}, 'card'),
        throwsAtPath('card.subtitle'),
      );
    });

    test('absent slots still yield the empty layout', () {
      expect(CardLayout.fromJson(const {}, 'card'), const CardLayout.empty());
    });
  });

  group('rules is deliberately NOT hardened', () {
    test('a malformed rules value reads as no rules instead of throwing', () {
      // ValidationRules are documented as client-side hints only, and the
      // server revalidates every submission — so a malformed value costs a 422
      // on submit rather than corrupting anything. Kept lenient on purpose.
      final component = SchemaComponent.fromJson(const {
        'type': 'text',
        'name': 'email',
        'rules': 'required',
      }, 'form[0]');

      expect(component.rules, const ValidationRules.none());
    });
  });

  group('a malformed list response degrades instead of throwing', () {
    Future<void> expectEmptyPage(Map<String, dynamic> body) async {
      final page = await sourceFor(
        FakeTransport({
          '/api/mobile-panel/schema': _panelJson,
          '/api/mobile-panel/banners': body,
        }),
      ).list('banners');

      expect(page.records, isEmpty);
      expect(page.meta.hasMore, isFalse);
    }

    test('`data` absent', () => expectEmptyPage({'meta': {}}));

    test('`data` is not a list', () => expectEmptyPage({'data': 'nope'}));

    test('a row that is not a map is skipped, its siblings survive', () async {
      final page = await sourceFor(
        FakeTransport({
          '/api/mobile-panel/schema': _panelJson,
          '/api/mobile-panel/banners': {
            'data': [
              'nope',
              {'id': 7, 'name': 'الأولى'},
            ],
            'meta': {},
          },
        }),
      ).list('banners');

      expect(page.records.single.id, 7);
    });

    test('`meta` absent yields a page that reports no more', () async {
      final page = await sourceFor(
        FakeTransport({
          '/api/mobile-panel/schema': _panelJson,
          '/api/mobile-panel/banners': {
            'data': [
              {'id': 7},
            ],
          },
        }),
      ).list('banners');

      expect(page.records, hasLength(1));
      expect(page.meta.hasMore, isFalse);
    });
  });
}
