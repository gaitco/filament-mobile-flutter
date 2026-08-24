import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/ports/filament_conditional_transport.dart';
import 'package:filament_mobile/ports/filament_schema_cache.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

/// A trivial in-memory [FilamentSchemaCache], for wiring tests only — the
/// store's own behaviour is covered by schema_cache_store_test.dart.
class _FakeSchemaCache implements FilamentSchemaCache {
  final _store = <String, CachedSchema>{};

  @override
  Future<CachedSchema?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, CachedSchema value) async =>
      _store[key] = value;

  @override
  Future<void> clear(String key) async => _store.remove(key);
}

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

  test('relation() builds the documented path and parses rows by the RELATED '
      "model's own recordKey, not the resource's", () async {
    // recordKey `slug`, not `id` — this is what proves rows are parsed by
    // `relation.recordKey` rather than a hardcoded `'id'` (the P6d Task 7
    // review's Important 2), and distinctly from the panel resource's own
    // `recordKey: 'id'` in `_panelJson` above.
    const tags = RelationDescriptor(
      key: 'tags',
      label: 'Tags',
      card: CardLayout.empty(),
      recordKey: 'slug',
    );

    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/banners/7/relations/tags': {
        'data': [
          {'slug': 'sale', 'name': 'Sale'},
        ],
        'meta': {
          'current_page': 1,
          'last_page': 2,
          'per_page': 15,
          'total': 16,
        },
      },
    });

    final page = await sourceFor(
      transport,
    ).relation('banners', 7, tags, page: 1);

    expect(page.records, hasLength(1));
    expect(page.records.single.id, 'sale');
    expect(page.records.single.get<String>('name'), 'Sale');
    expect(page.meta.hasMore, isTrue);

    final call = transport.calls.last;
    expect(call.path, '/api/mobile-panel/banners/7/relations/tags');
    expect(call.query, {'page': '1'});
  });

  test(
    'relation() builds the same search/sort query list() builds (P11)',
    () async {
      const tags = RelationDescriptor(
        key: 'tags',
        label: 'Tags',
        card: CardLayout.empty(),
      );

      final transport = FakeTransport({
        '/api/mobile-panel/schema': _panelJson,
        '/api/mobile-panel/banners/7/relations/tags': {'data': [], 'meta': {}},
      });

      await sourceFor(transport).relation(
        'banners',
        7,
        tags,
        page: 1,
        search: 'sale',
        sort: 'name',
        direction: 'desc',
      );

      expect(transport.calls.last.query, {
        'page': '1',
        'search': 'sale',
        'sort': 'name',
        'direction': 'desc',
      });
    },
  );

  test('relation() omits absent or blank search/sort params, like list() — '
      'an unknown sort key is a 422 server-side, never sent as null', () async {
    const tags = RelationDescriptor(
      key: 'tags',
      label: 'Tags',
      card: CardLayout.empty(),
    );

    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/banners/7/relations/tags': {'data': [], 'meta': {}},
    });

    await sourceFor(
      transport,
    ).relation('banners', 7, tags, search: '   ', sort: ' ', direction: '');

    expect(transport.calls.last.query, {'page': '1'});
  });

  test(
    'relation() sends the requested page, not a hardcoded first page',
    () async {
      // Task 8 pages through this same call. A `page: 2` that reached the wire
      // as `'page': '1'` would still return 200 against this fake (it ignores
      // the query) and every other assertion here would stay green — the
      // outgoing query is the only thing that can catch that regression.
      const tags = RelationDescriptor(
        key: 'tags',
        label: 'Tags',
        card: CardLayout.empty(),
      );

      final transport = FakeTransport({
        '/api/mobile-panel/schema': _panelJson,
        '/api/mobile-panel/banners/7/relations/tags': {
          'data': [],
          'meta': {
            'current_page': 2,
            'last_page': 2,
            'per_page': 15,
            'total': 16,
          },
        },
      });

      await sourceFor(transport).relation('banners', 7, tags, page: 2);

      expect(transport.calls.last.query, {'page': '2'});
    },
  );

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

  test('list() sends a single-value filter as filter[name]=value', () async {
    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/banners': {'data': [], 'meta': {}},
    });

    await sourceFor(transport).list('banners', filters: {'status': 'draft'});

    expect(transport.calls.last.query, {
      'page': '1',
      'filter[status]': 'draft',
    });
  });

  test(
    'list() sends a multiple filter as indexed keys, never filter[name][]',
    () async {
      // Load-bearing: FilamentTransport.get() hands the host a FLAT map and
      // the reference host stringifies every value, so a raw List<String>
      // here would go out as the literal "[a, b]". See the doc on
      // ResourceDataSource.list() for the full reasoning.
      final transport = FakeTransport({
        '/api/mobile-panel/schema': _panelJson,
        '/api/mobile-panel/banners': {'data': [], 'meta': {}},
      });

      await sourceFor(transport).list(
        'banners',
        filters: {
          'tags': ['a', 'b'],
        },
      );

      expect(transport.calls.last.query, {
        'page': '1',
        'filter[tags][0]': 'a',
        'filter[tags][1]': 'b',
      });
    },
  );

  test('list() sends no filter key at all when filters is empty', () async {
    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/banners': {'data': [], 'meta': {}},
    });

    await sourceFor(transport).list('banners');

    expect(
      transport.calls.last.query!.keys.any((k) => k.startsWith('filter')),
      isFalse,
    );
  });

  // Review fix round 1: an explicitly-cleared filter must reach the wire as
  // the bare `filter[name]=` the server reads as "any" — mobile-core's
  // ListQuery::filters() treats an OMITTED key as "apply this filter's
  // default", so "send nothing" (the empty-map case above) is NOT the same
  // request as "send an explicit clear".
  test(
    'list() sends filter[status]= for an explicitly cleared single filter',
    () async {
      final transport = FakeTransport({
        '/api/mobile-panel/schema': _panelJson,
        '/api/mobile-panel/banners': {'data': [], 'meta': {}},
      });

      await sourceFor(transport).list('banners', filters: {'status': ''});

      expect(transport.calls.last.query, {'page': '1', 'filter[status]': ''});
    },
  );

  test('list() sends filter[tags]= for an explicitly cleared multiple filter — '
      'an empty List, not zero indexed keys, since a query string cannot '
      'express an empty list', () async {
    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/banners': {'data': [], 'meta': {}},
    });

    await sourceFor(transport).list('banners', filters: {'tags': <String>[]});

    expect(transport.calls.last.query, {'page': '1', 'filter[tags]': ''});
  });

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

  test(
    'cachedPanel() and panel() are wired through to the schema cache',
    () async {
      final cache = _FakeSchemaCache();
      final transport = FakeConditionalTransport(
        const {},
        conditionalResponses: {
          '/api/mobile-panel/schema': [
            ConditionalResponse(
              notModified: false,
              body: _panelJson,
              etag: '"abc"',
            ),
          ],
        },
      );
      final source = RestResourceDataSource(
        transport: transport,
        cache: cache,
        cacheKey: 'user:1',
      );

      expect(await source.cachedPanel(), isNull);

      final panel = await source.panel();

      expect(panel.resources.single.key, 'banners');
      expect((await cache.read('user:1'))?.etag, '"abc"');
    },
  );

  test('pollable reads reuse their body on a conditional 304', () async {
    final listBody = <String, dynamic>{
      'data': [
        {'id': 7, 'name': 'Cached'},
      ],
      'meta': {'current_page': 1, 'last_page': 1},
    };
    final transport = FakeConditionalTransport(
      const {},
      conditionalResponses: {
        '/api/mobile-panel/schema': [
          ConditionalResponse(
            notModified: false,
            body: _panelJson,
            etag: '"schema"',
          ),
        ],
        '/api/mobile-panel/banners?page=1': [
          ConditionalResponse(
            notModified: false,
            body: listBody,
            etag: '"list"',
          ),
          const ConditionalResponse(notModified: true),
        ],
      },
    );
    final source = sourceFor(transport);

    final first = await source.list('banners');
    final second = await source.list('banners');

    expect(first.records.single.id, 7);
    expect(second.records.single.get<String>('name'), 'Cached');
    expect(transport.conditionalCalls.last.etag, '"list"');
  });

  test('filterOptions posts the filter query and parses its page', () async {
    final transport = FakeTransport(
      const {},
      writes: {
        'POST /api/mobile-panel/banners/filter-options': const FilamentResponse(
          statusCode: 200,
          body: {
            'options': [
              {'value': 'active', 'label': 'Active'},
            ],
            'hasMore': true,
          },
        ),
      },
    );

    final page = await sourceFor(
      transport,
    ).filterOptions('banners', filter: 'status', query: 'act');

    expect(
      page,
      const OptionsPage(
        options: [SelectOption(value: 'active', label: 'Active')],
        hasMore: true,
      ),
    );
    expect(
      transport.calls.single.path,
      '/api/mobile-panel/banners/filter-options',
    );
    expect(transport.calls.single.body, {'filter': 'status', 'q': 'act'});
  });
}
