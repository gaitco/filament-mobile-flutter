import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

void main() {
  // The whole point of the port change: a 422 is DATA, not a throw. The host
  // owns HTTP; the package owns what a status means. A host that had to
  // recognise 422 itself would fail quietly the day it forgot.
  test('a 422 becomes WriteInvalid carrying per-field messages', () async {
    final source = RestResourceDataSource(
      transport: FakeTransport(
        const {},
        writes: {
          'POST /api/mobile-panel/banners': FilamentResponse(
            statusCode: 422,
            body: {
              'errors': {
                'name': ['The name field is required.'],
              },
            },
          ),
        },
      ),
    );

    final result = await source.create('banners', {'name': ''});

    expect(result, isA<WriteInvalid>());
    expect((result as WriteInvalid).errors['name'], [
      'The name field is required.',
    ]);
  });

  test('a 403 becomes WriteDenied, not an exception', () async {
    final source = RestResourceDataSource(
      transport: FakeTransport(
        const {},
        writes: {
          'PUT /api/mobile-panel/banners/7': FilamentResponse(
            statusCode: 403,
            body: {'message': 'This action is unauthorized.'},
          ),
        },
      ),
    );

    expect(await source.update('banners', 7, {}), isA<WriteDenied>());
  });

  test(
    'a 404 on delete becomes WriteGone — already deleted is not an error',
    () async {
      final source = RestResourceDataSource(
        transport: FakeTransport(
          const {},
          writes: {
            'DELETE /api/mobile-panel/banners/7': FilamentResponse(
              statusCode: 404,
              body: {'message': 'No [banners] record [7].'},
            ),
          },
        ),
      );

      expect(await source.destroy('banners', 7), isA<WriteGone>());
    },
  );

  test(
    'a transport throw becomes WriteFailed carrying the host message',
    () async {
      final source = RestResourceDataSource(
        transport: ThrowingTransport(
          const FilamentTransportException('لا يوجد اتصال'),
        ),
      );

      final result = await source.create('banners', const {});

      expect(result, isA<WriteFailed>());
      expect((result as WriteFailed).message, 'لا يوجد اتصال');
    },
  );

  test('a transport throw on runAction becomes ActionFailed, not an unhandled '
      'error', () async {
    // Same contract as the writes above: the transport throws on
    // socket/DNS/timeout, and a tapped action button with no network must
    // surface as a failed action — not an unhandled async error the user
    // never sees.
    final source = RestResourceDataSource(
      transport: ThrowingTransport(
        const FilamentTransportException('لا يوجد اتصال'),
      ),
    );

    final result = await source.runAction('banners', 7, 'approve');

    expect(result, isA<ActionFailed>());
    expect((result as ActionFailed).message, 'لا يوجد اتصال');
  });

  test('a 422 whose errors block is malformed still reports invalid', () async {
    // Degrading to "no field errors" is right; throwing here would turn a
    // recoverable validation failure into a dead form.
    final source = RestResourceDataSource(
      transport: FakeTransport(
        const {},
        writes: {
          'POST /api/mobile-panel/banners': FilamentResponse(
            statusCode: 422,
            body: {'errors': 'nope'},
          ),
        },
      ),
    );

    final result = await source.create('banners', const {});

    expect(result, isA<WriteInvalid>());
    expect((result as WriteInvalid).errors, isEmpty);
  });

  // Unlike the writes, state() has no result union to carry a denial or a
  // 404 into — its contract is "the current form". These three pin the
  // guard that closes the gap: a non-2xx must throw, never degrade into an
  // empty form via listFromJson's "missing key reads as []" rule.
  test('state() parses a 200 through the same parser as /schema', () async {
    final source = RestResourceDataSource(
      transport: FakeTransport(
        const {},
        writes: {
          'POST /api/mobile-panel/banners/state': FilamentResponse(
            statusCode: 200,
            body: {
              'components': [
                {'type': 'text', 'name': 'name'},
              ],
            },
          ),
        },
      ),
    );

    final components = await source.state(
      'banners',
      values: const {},
      changed: 'name',
    );

    expect(components, [
      SchemaComponent.fromJson(const {
        'type': 'text',
        'name': 'name',
      }, 'components[0]'),
    ]);
  });

  test('state() throws on 403 rather than returning an empty form', () async {
    final source = RestResourceDataSource(
      transport: FakeTransport(
        const {},
        writes: {
          'POST /api/mobile-panel/banners/state': FilamentResponse(
            statusCode: 403,
            body: {'message': 'This action is unauthorized.'},
          ),
        },
      ),
    );

    expect(
      () => source.state('banners', values: const {}, changed: 'name'),
      throwsA(isA<FilamentTransportException>()),
    );
  });

  test('state() throws on 404 rather than returning an empty form', () async {
    final source = RestResourceDataSource(
      transport: FakeTransport(
        const {},
        writes: {
          'POST /api/mobile-panel/banners/state': FilamentResponse(
            statusCode: 404,
            body: {'message': 'No mobile resource [banners].'},
          ),
        },
      ),
    );

    expect(
      () => source.state('banners', values: const {}, changed: 'name'),
      throwsA(isA<FilamentTransportException>()),
    );
  });

  test(
    'a 204 with a stripped body on delete still becomes WriteSuccess',
    () async {
      final source = RestResourceDataSource(
        transport: FakeTransport(
          const {},
          writes: {
            'DELETE /api/mobile-panel/banners/7': const FilamentResponse(
              statusCode: 204,
              body: {},
            ),
          },
        ),
      );

      final result = await source.destroy('banners', 7);

      expect(result, isA<WriteSuccess>());
      expect((result as WriteSuccess).data, isEmpty);
    },
  );

  // The relation-row writes (P9): the same sibling URL family the relation
  // read already lives on, the same status-to-result mapping as the resource
  // writes above. The child id in the URL is the relation's `recordKey`
  // value — routinely NOT `id`, which is why these tests write it as a slug.
  group('relation writes', () {
    const relation = RelationDescriptor(
      key: 'tags',
      label: 'Tags',
      card: CardLayout(titleField: 'name'),
    );

    test('createRelation POSTs to the relation collection and a 201 with the '
        'row is WriteSuccess', () async {
      final transport = FakeTransport(
        const {},
        writes: {
          'POST /api/mobile-panel/banners/7/relations/tags':
              const FilamentResponse(
                statusCode: 201,
                body: {
                  'data': {'name': 'sale'},
                },
              ),
        },
      );
      final source = RestResourceDataSource(transport: transport);

      final result = await source.createRelation('banners', 7, relation, {
        'name': 'sale',
      });

      expect(result, isA<WriteSuccess>());
      expect((result as WriteSuccess).data['name'], 'sale');
      expect(
        transport.calls.single.path,
        '/api/mobile-panel/banners/7/relations/tags',
      );
    });

    test('updateRelation PUTs to the child row, keyed by the relation\'s '
        'recordKey value', () async {
      final transport = FakeTransport(
        const {},
        writes: {
          'PUT /api/mobile-panel/banners/7/relations/tags/sale':
              const FilamentResponse(statusCode: 200, body: {'data': {}}),
        },
      );
      final source = RestResourceDataSource(transport: transport);

      final result = await source.updateRelation(
        'banners',
        7,
        relation,
        'sale',
        {'name': 'sale'},
      );

      expect(result, isA<WriteSuccess>());
      expect(
        transport.calls.single.path,
        '/api/mobile-panel/banners/7/relations/tags/sale',
      );
    });

    test(
      'deleteRelation DELETEs the child row through the relationship',
      () async {
        final transport = FakeTransport(
          const {},
          writes: {
            'DELETE /api/mobile-panel/banners/7/relations/tags/sale':
                const FilamentResponse(statusCode: 200, body: {'data': {}}),
          },
        );
        final source = RestResourceDataSource(transport: transport);

        final result = await source.deleteRelation(
          'banners',
          7,
          relation,
          'sale',
        );

        expect(result, isA<WriteSuccess>());
      },
    );

    test('a 422 becomes WriteInvalid keyed by the CHILD form\'s field names — '
        'the same mapping a resource write gets', () async {
      final source = RestResourceDataSource(
        transport: FakeTransport(
          const {},
          writes: {
            'POST /api/mobile-panel/banners/7/relations/tags':
                const FilamentResponse(
                  statusCode: 422,
                  body: {
                    'errors': {
                      'name': ['The name field is required.'],
                    },
                  },
                ),
          },
        ),
      );

      final result = await source.createRelation(
        'banners',
        7,
        relation,
        const {},
      );

      expect(result, isA<WriteInvalid>());
      expect((result as WriteInvalid).errors['name'], [
        'The name field is required.',
      ]);
    });

    test('a cross-parent child id comes back as WriteGone (404), and a '
        'transport throw as WriteFailed', () async {
      final gone = RestResourceDataSource(
        transport: FakeTransport(
          const {},
          writes: {
            'DELETE /api/mobile-panel/banners/7/relations/tags/not-mine':
                const FilamentResponse(statusCode: 404, body: {}),
          },
        ),
      );
      expect(
        await gone.deleteRelation('banners', 7, relation, 'not-mine'),
        isA<WriteGone>(),
      );

      final offline = RestResourceDataSource(
        transport: const ThrowingTransport(
          FilamentTransportException('لا يوجد اتصال'),
        ),
      );
      final result = await offline.updateRelation(
        'banners',
        7,
        relation,
        'sale',
        const {},
      );
      expect(result, isA<WriteFailed>());
      expect((result as WriteFailed).message, 'لا يوجد اتصال');
    });
  });
}
