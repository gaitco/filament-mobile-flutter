import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
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
      'card': {
        'title': {'field': 'name'},
      },
    },
  ],
};

RestResourceDataSource sourceFor(FakeTransport transport) =>
    RestResourceDataSource(transport: transport);

void main() {
  test('panel() parses the schema document', () async {
    final transport = FakeTransport({'/api/mobile-panel/schema': _panelJson});

    final panel = await sourceFor(transport).panel();

    expect(panel.resources.single.key, 'banners');
    expect(transport.calls.single.path, '/api/mobile-panel/schema');
  });

  test('list() builds the documented query and parses records', () async {
    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/banners': {
        'data': [
          {'id': 7, 'name': 'الأولى'},
          {'id': 8, 'name': 'الثانية'},
        ],
        'meta': {
          'current_page': 1,
          'last_page': 2,
          'per_page': 20,
          'total': 25,
        },
      },
    });

    final page = await sourceFor(transport).list(
      'banners',
      page: 1,
      search: 'الأول',
      sort: 'created_at',
      direction: 'desc',
    );

    expect(page.records, hasLength(2));
    expect(page.records.first.id, 7);
    expect(page.records.first.get<String>('name'), 'الأولى');
    expect(page.meta.hasMore, isTrue);

    final listCall = transport.calls.last;
    expect(listCall.path, '/api/mobile-panel/banners');
    expect(listCall.query, {
      'page': '1',
      'search': 'الأول',
      'sort': 'created_at',
      'direction': 'desc',
    });
  });

  test(
    'list() omits absent query parameters rather than sending nulls',
    () async {
      final transport = FakeTransport({
        '/api/mobile-panel/schema': _panelJson,
        '/api/mobile-panel/banners': {'data': [], 'meta': {}},
      });

      await sourceFor(transport).list('banners');

      expect(transport.calls.last.query, {'page': '1'});
    },
  );

  test('list() sends no search when the term is blank', () async {
    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/banners': {'data': [], 'meta': {}},
    });

    await sourceFor(transport).list('banners', search: '   ');

    expect(transport.calls.last.query!.containsKey('search'), isFalse);
  });

  test('record() parses the per-record permissions block', () async {
    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/banners/7': {
        'data': {'id': 7, 'name': 'الأولى'},
        'permissions': {'view': true, 'update': false, 'delete': false},
      },
    });

    final record = await sourceFor(transport).record('banners', 7);

    expect(record.id, 7);
    expect(record.can('view'), isTrue);
    expect(record.can('delete'), isFalse);
  });

  test(
    'a record response with no permissions block denies everything',
    () async {
      final transport = FakeTransport({
        '/api/mobile-panel/schema': _panelJson,
        '/api/mobile-panel/banners/7': {
          'data': {'id': 7},
        },
      });

      final record = await sourceFor(transport).record('banners', 7);

      expect(record.can('view'), isFalse);
    },
  );

  test('honours a resource recordKey that is not id', () async {
    final transport = FakeTransport({
      '/api/mobile-panel/schema': {
        'version': 1,
        'panel': {'id': 'mobile', 'title': 't'},
        'resources': [
          {
            'key': 'posts',
            'labels': {'singular': 'a', 'plural': 'b'},
            'recordKey': 'uuid',
          },
        ],
      },
      '/api/mobile-panel/posts': {
        'data': [
          {'uuid': 'abc', 'title': 'x'},
        ],
        'meta': {},
      },
    });

    final page = await sourceFor(transport).list('posts');

    expect(page.records.single.id, 'abc');
  });

  test('throws a clear error for a resource absent from the panel', () async {
    final transport = FakeTransport({'/api/mobile-panel/schema': _panelJson});

    expect(
      () => sourceFor(transport).list('ghosts'),
      throwsA(isA<StateError>()),
    );
  });

  test('fetches the schema once and reuses it', () async {
    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/banners': {'data': [], 'meta': {}},
    });
    final source = sourceFor(transport);

    await source.list('banners');
    await source.list('banners', page: 2);

    final schemaCalls = transport.calls
        .where((call) => call.path.endsWith('/schema'))
        .length;
    expect(schemaCalls, 1);
  });

  // The default has to be absolute: a host's Dio baseUrl conventionally has no
  // trailing slash, so a relative prefix builds `example.comapi/...` and fails
  // DNS on the integrator's first request.
  test('the default prefix is absolute', () async {
    final transport = FakeTransport({'/api/mobile-panel/schema': _panelJson});

    await sourceFor(transport).panel();

    expect(transport.calls.single.path, '/api/mobile-panel/schema');
  });

  test('normalises a host-supplied prefix to one leading, no trailing '
      'slash', () async {
    for (final supplied in ['api/v2/panel/', '/api/v2/panel', 'api/v2/panel']) {
      final transport = FakeTransport({'/api/v2/panel/schema': _panelJson});

      await RestResourceDataSource(
        transport: transport,
        prefix: supplied,
      ).panel();

      expect(
        transport.calls.single.path,
        '/api/v2/panel/schema',
        reason: '`$supplied` should normalise',
      );
    }
  });

  // The write pilot could not make a single request: its host has no Dio
  // base URL for the panel, so it passes the whole origin as the prefix — as
  // the read pilot's own report told it to. Prepending a slash turned that
  // into the relative path `/https:/your-panel.test/api/mobile-panel`, and every
  // request 404'd.
  test('a prefix that is a whole URL is left absolute', () async {
    for (final supplied in [
      'https://your-panel.test/api/mobile-panel',
      'https://your-panel.test/api/mobile-panel/',
      'http://localhost:8000/api/mobile-panel',
    ]) {
      final expected = supplied.replaceAll(RegExp(r'/+$'), '');
      final transport = FakeTransport({'$expected/schema': _panelJson});

      await RestResourceDataSource(
        transport: transport,
        prefix: supplied,
      ).panel();

      expect(
        transport.calls.single.path,
        '$expected/schema',
        reason: '`$supplied` must not be turned into a relative path',
      );
    }
  });

  test(
    'an empty prefix stays empty rather than becoming a bare slash',
    () async {
      // Carried in the ledger since an earlier phase: `''` and `'/'` both used
      // to normalise to `'/'`, so every path built `//schema`.
      for (final supplied in ['', '/', '  ']) {
        final transport = FakeTransport({'/schema': _panelJson});

        await RestResourceDataSource(
          transport: transport,
          prefix: supplied,
        ).panel();

        expect(transport.calls.single.path, '/schema', reason: '`$supplied`');
      }
    },
  );

  test('sends no sort or direction when they are whitespace', () async {
    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/banners': {'data': [], 'meta': {}},
    });

    await sourceFor(transport).list('banners', sort: '  ', direction: ' ');

    expect(transport.calls.last.query, {'page': '1'});
  });

  test('record() parses the actions the server published for it', () async {
    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/banners/7': {
        'data': {'id': 7},
        'permissions': {},
        'actions': [
          {
            'name': 'approve',
            'label': 'Approve',
            'color': 'success',
            'icon': 'heroicon-o-check',
            'confirmation': null,
          },
        ],
      },
    });

    final record = await sourceFor(transport).record('banners', 7);

    expect(record.actions.single.name, 'approve');
  });

  test('runAction posts to the action endpoint and reports success', () async {
    final transport = FakeTransport(
      const {},
      writes: {
        'POST /api/mobile-panel/banners/7/actions/approve':
            const FilamentResponse(
              statusCode: 200,
              body: {'message': 'Approved'},
            ),
      },
    );
    final source = sourceFor(transport);

    final result = await source.runAction('banners', 7, 'approve');

    expect(result, isA<ActionSuccess>());
    expect((result as ActionSuccess).message, 'Approved');
  });

  test(
    'a 422 is a failure carrying the server message, not a thrown error',
    () async {
      final transport = FakeTransport(
        const {},
        writes: {
          'POST /api/mobile-panel/banners/7/actions/halting':
              const FilamentResponse(
                statusCode: 422,
                body: {'message': 'Cannot do that yet'},
              ),
        },
      );
      final source = sourceFor(transport);

      final result = await source.runAction('banners', 7, 'halting');

      expect(result, isA<ActionFailed>());
      expect((result as ActionFailed).message, 'Cannot do that yet');
    },
  );
}
