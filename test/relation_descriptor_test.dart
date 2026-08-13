import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/schema/json_reader.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden_transport.dart';

const minimalResourceJson = {
  'key': 'posts',
  'labels': {'singular': 'a', 'plural': 'b'},
};

void main() {
  group('RelationDescriptor', () {
    test('parses a relation with its key, label and card', () {
      // Wire shape taken from the real BannerResource fixture: each card slot
      // is `{"field": …}`, not a bare string — see CardLayout.fromJson.
      final relation = RelationDescriptor.fromJson(const {
        'key': 'tags',
        'label': 'Tags',
        'card': {
          'title': {'field': 'name'},
        },
      }, 'resources[0].relations[0]');

      expect(relation.key, 'tags');
      expect(relation.label, 'Tags');
      expect(relation.card.titleField, 'name');
      expect(relation.card.subtitleField, isNull);
      // Absent from this fixture's JSON — the default, covered in its own
      // test below alongside the non-default wire shape.
      expect(relation.recordKey, 'id');
    });

    test('parses the related model\'s own recordKey off the wire', () {
      // The related model is routinely NOT `id`-routed (a slug, a uuid) —
      // this is what a client needs to parse its rows without assuming `id`.
      final relation = RelationDescriptor.fromJson(const {
        'key': 'tags',
        'label': 'Tags',
        'card': {
          'title': {'field': 'name'},
        },
        'recordKey': 'name',
      }, 'resources[0].relations[0]');

      expect(relation.recordKey, 'name');
    });

    test('a relation missing key throws', () {
      expect(
        () => RelationDescriptor.fromJson(const {
          'label': 'Tags',
          'card': {
            'title': {'field': 'name'},
          },
        }, 'resources[0].relations[0]'),
        throwsA(isA<SchemaFormatException>()),
      );
    });

    test('a card that fills no slot drops the relation', () {
      // The field matrix that found this: every other missing required field
      // dropped the relation, but an absent, null or `{}` card was PUBLISHED
      // with an all-null layout that rendered zero widgets — a heading over
      // nothing, while `listFromJson`'s doc claimed "a bad card is dropped".
      // `{}` is unreachable from today's server (PHP encodes an empty card as
      // `[]`, which `object()` already rejects) but absent and null are not,
      // and the server-side refusal has a client half by design.
      for (final card in [null, const <String, dynamic>{}]) {
        expect(
          () => RelationDescriptor.fromJson({
            'key': 'tags',
            'label': 'Tags',
            if (card != null) 'card': card,
          }, 'resources[0].relations[0]'),
          throwsA(isA<SchemaFormatException>()),
          reason: 'card: $card',
        );
      }

      expect(
        RelationDescriptor.listFromJson(const {
          'relations': [
            {'key': 'tags', 'label': 'Tags'},
          ],
        }, 'resources[0]'),
        isEmpty,
      );
    });

    test('equality is by key', () {
      final a = RelationDescriptor.fromJson(const {
        'key': 'tags',
        'label': 'Tags',
        'card': {
          'title': {'field': 'name'},
        },
      }, 'r');
      final b = RelationDescriptor.fromJson(const {
        'key': 'tags',
        'label': 'Different',
        'card': {
          'title': {'field': 'other'},
        },
      }, 'r');

      expect(a, b);
    });

    test(
      'parses the child resource key when the server publishes one (P9)',
      () {
        final relation = RelationDescriptor.fromJson(const {
          'key': 'tags',
          'label': 'Tags',
          'card': {
            'title': {'field': 'name'},
          },
          'resource': 'tags',
        }, 'r');

        expect(relation.resource, 'tags');
      },
    );

    test('an absent, null or wrong-typed resource key reads as read-only, '
        'never throws', () {
      // Absent: a server predating P9. Null: a server whose relation child
      // resolves to zero or several mobile resources encodes it as absent —
      // and a client must tolerate the literal too. Wrong type: `opt`'s
      // standing licence, a scalar the server widened. All three are the
      // same statement — read-only — and none is a malformed relation.
      for (final node in [
        const <String, dynamic>{},
        const {'resource': null},
        const {'resource': 42},
      ]) {
        final relation = RelationDescriptor.fromJson({
          'key': 'tags',
          'label': 'Tags',
          'card': {
            'title': {'field': 'name'},
          },
          ...node,
        }, 'r');

        expect(relation.resource, isNull, reason: 'node: $node');
      }
    });
  });

  group('ResourceSchema.relations', () {
    test('an absent relations key reads as no relations, not an error', () {
      // An older server predating P6d publishes no key at all. That is a
      // server without relation support, not a malformed contract.
      final resource = ResourceSchema.fromJson(
        minimalResourceJson,
        'resources[0]',
      );

      expect(resource.relations, isEmpty);
    });

    test('a malformed relation is dropped, not fatal to the resource', () {
      // One bad relation must not cost the whole resource — the same rule
      // the repeater's item template already follows.
      final resource = ResourceSchema.fromJson({
        ...minimalResourceJson,
        'relations': [
          {
            'key': 'good',
            'label': 'Good',
            'card': {
              'title': {'field': 'name'},
            },
          },
          {'no_key': true},
          'not even an object',
        ],
      }, 'resources[0]');

      expect(resource.relations.map((r) => r.key), ['good']);
    });

    test('relations present but not a list is a contract violation', () {
      expect(
        () => ResourceSchema.fromJson({
          ...minimalResourceJson,
          'relations': 'not-a-list',
        }, 'resources[0]'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'resources[0].relations',
          ),
        ),
      );
    });

    test('parses the real BannerResource relation from the committed contract '
        'snapshot, not an empty PostResource array', () async {
      // PostResource publishes `relations: []` — asserting against it would
      // pass whether or not parsing worked at all. BannerResource carries a
      // real TagsRelationManager, so this exercises the actual wire shape.
      final panel = await RestResourceDataSource(
        transport: GoldenTransport(),
      ).panel();

      final banners = panel.resource('banners')!;
      expect(banners.relations, isNotEmpty);
      expect(banners.relations.single.key, 'tags');
      expect(banners.relations.single.label, 'Tags');
      expect(banners.relations.single.card.titleField, 'name');
      // The fixture's Tag model deliberately routes on `name`, not `id` — see
      // the Laravel-side RelationSchemaTest for why. This is the real
      // recordKey a live panel sends, not a value chosen to make parsing
      // trivially pass.
      expect(banners.relations.single.recordKey, 'name');

      final posts = panel.resource('posts')!;
      expect(posts.relations, isEmpty);
    });

    test('a relation carries its owning resource\'s direction, not the '
        'library default — the same propagation PanelSchema.fromJson does '
        'for the resource itself, one level deeper', () {
      final resource = ResourceSchema.fromJson(
        {
          ...minimalResourceJson,
          'relations': [
            {
              'key': 'tags',
              'label': 'Tags',
              'card': {
                'title': {'field': 'name'},
              },
            },
          ],
        },
        'resources[0]',
        direction: PanelDirection.rtl,
      );

      expect(resource.relations.single.direction, PanelDirection.rtl);
    });

    test('a relation built without an explicit direction defaults to ltr, like '
        'ResourceSchema.direction does', () {
      final relation = RelationDescriptor.fromJson(const {
        'key': 'tags',
        'label': 'Tags',
        'card': {
          'title': {'field': 'name'},
        },
      }, 'r');

      expect(relation.direction, PanelDirection.ltr);
    });
  });
}
