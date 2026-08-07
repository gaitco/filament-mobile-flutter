import 'dart:convert';

import 'package:filament_mobile/data/schema_cache_store.dart';
import 'package:filament_mobile/ports/filament_conditional_transport.dart';
import 'package:filament_mobile/ports/filament_schema_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

const _path = '/api/mobile-panel/schema';
const _key = 'user:1';

Map<String, dynamic> get _panelJson => {
  'version': 1,
  'panel': {'id': 'mobile', 'title': 'Panel'},
  'resources': [
    {
      'key': 'banners',
      'labels': {'singular': 'Banner', 'plural': 'Banners'},
      'recordKey': 'id',
    },
  ],
};

Map<String, dynamic> get _newPanelJson => {
  'version': 1,
  'panel': {'id': 'mobile', 'title': 'New Panel'},
  'resources': [
    {
      'key': 'posts',
      'labels': {'singular': 'Post', 'plural': 'Posts'},
      'recordKey': 'id',
    },
  ],
};

/// Records every read/write/clear call, so a test can assert a cache was — or
/// deliberately was not — touched.
class _FakeSchemaCache implements FilamentSchemaCache {
  final _store = <String, CachedSchema>{};
  int readCount = 0;
  int writeCount = 0;
  int clearCount = 0;

  void seed(String key, CachedSchema value) => _store[key] = value;

  @override
  Future<CachedSchema?> read(String key) async {
    readCount++;
    return _store[key];
  }

  @override
  Future<void> write(String key, CachedSchema value) async {
    writeCount++;
    _store[key] = value;
  }

  @override
  Future<void> clear(String key) async {
    clearCount++;
    _store.remove(key);
  }
}

/// A cache whose `write()` throws, so a test can prove persistence failing
/// never breaks a working fetch.
class _ThrowingWriteCache implements FilamentSchemaCache {
  @override
  Future<CachedSchema?> read(String key) async => null;

  @override
  Future<void> write(String key, CachedSchema value) async =>
      throw StateError('storage is full');

  @override
  Future<void> clear(String key) async {}
}

/// A cache whose `read()` throws — a closed Hive box, a corrupted
/// preferences entry, any storage I/O error — so a test can prove that
/// failure never breaks a working fetch either.
class _ThrowingReadCache implements FilamentSchemaCache {
  @override
  Future<CachedSchema?> read(String key) async =>
      throw StateError('storage is unreadable');

  @override
  Future<void> write(String key, CachedSchema value) async {}

  @override
  Future<void> clear(String key) async {}
}

void main() {
  // 1. No cache and no conditional transport → panel() behaves exactly as
  // today (one plain get()); cachedPanel() returns null. No regression is
  // the headline property.
  test('no cache and no conditional transport: panel() does a plain get(), '
      'cachedPanel() is null', () async {
    final transport = FakeTransport({_path: _panelJson});
    final store = SchemaCacheStore(transport: transport, path: _path);

    expect(await store.cachedPanel(), isNull);

    final panel = await store.panel();

    expect(panel.resources.single.key, 'banners');
    expect(transport.calls.single.path, _path);
  });

  // 2. Cache present but empty → cachedPanel() null; after panel() the cache
  // holds the document and the ETag the server sent.
  test('cache present but empty: cachedPanel() is null; panel() populates the '
      'cache with the document and etag', () async {
    final cache = _FakeSchemaCache();
    final transport = FakeConditionalTransport(
      const {},
      conditionalResponses: {
        _path: [
          ConditionalResponse(
            notModified: false,
            body: _panelJson,
            etag: '"abc"',
          ),
        ],
      },
    );
    final store = SchemaCacheStore(
      transport: transport,
      path: _path,
      cache: cache,
      cacheKey: _key,
    );

    expect(await store.cachedPanel(), isNull);

    final panel = await store.panel();
    expect(panel.resources.single.key, 'banners');

    final stored = await cache.read(_key);
    expect(stored, isNotNull);
    expect(stored!.etag, '"abc"');
    expect(jsonDecode(stored.document), _panelJson);
  });

  // 3. Cache holds a document → cachedPanel() returns a parsed PanelSchema
  // with zero network calls.
  test(
    'cache holds a document: cachedPanel() parses it with zero network calls',
    () async {
      final cache = _FakeSchemaCache()
        ..seed(
          _key,
          CachedSchema(document: jsonEncode(_panelJson), etag: '"abc"'),
        );
      final transport = FakeTransport(const {});
      final store = SchemaCacheStore(
        transport: transport,
        path: _path,
        cache: cache,
        cacheKey: _key,
      );

      final panel = await store.cachedPanel();

      expect(panel, isNotNull);
      expect(panel!.resources.single.key, 'banners');
      expect(transport.calls, isEmpty);
    },
  );

  // 4. Conditional transport + cached etag → panel() sends that etag; on
  // notModified: true the cached document is used and the cache is not
  // rewritten.
  test('conditional transport + cached etag: panel() sends the etag; a 304 '
      'returns the cached document and does not rewrite the cache', () async {
    final cache = _FakeSchemaCache()
      ..seed(
        _key,
        CachedSchema(document: jsonEncode(_panelJson), etag: '"abc"'),
      );
    final transport = FakeConditionalTransport(
      const {},
      conditionalResponses: {
        _path: [const ConditionalResponse(notModified: true)],
      },
    );
    final store = SchemaCacheStore(
      transport: transport,
      path: _path,
      cache: cache,
      cacheKey: _key,
    );

    final panel = await store.panel();

    expect(panel.resources.single.key, 'banners');
    expect(transport.conditionalCalls.single.etag, '"abc"');
    expect(cache.writeCount, 0);
  });

  // 5. 200 with a new etag → the panel is the new one; the cache now holds
  // the new document and etag.
  test('200 with a new etag replaces the panel and the cache', () async {
    final cache = _FakeSchemaCache()
      ..seed(
        _key,
        CachedSchema(document: jsonEncode(_panelJson), etag: '"old"'),
      );
    final transport = FakeConditionalTransport(
      const {},
      conditionalResponses: {
        _path: [
          ConditionalResponse(
            notModified: false,
            body: _newPanelJson,
            etag: '"new"',
          ),
        ],
      },
    );
    final store = SchemaCacheStore(
      transport: transport,
      path: _path,
      cache: cache,
      cacheKey: _key,
    );

    final panel = await store.panel();

    expect(panel.resources.single.key, 'posts');

    final stored = await cache.read(_key);
    expect(stored!.etag, '"new"');
    expect(jsonDecode(stored.document), _newPanelJson);
  });

  // 6. A cached document of an unsupported contract version →
  // cachedPanel() returns null AND clears the entry — never throws
  // UnsupportedSchemaVersionException. The sharpest test in the task: a
  // stale cache must never trigger the "update your app" screen.
  test('a cached document of an unsupported version: cachedPanel() returns '
      'null and clears the entry, never throws', () async {
    final cache = _FakeSchemaCache()
      ..seed(
        _key,
        CachedSchema(
          document: jsonEncode({..._panelJson, 'version': 99}),
          etag: '"abc"',
        ),
      );
    final store = SchemaCacheStore(
      transport: FakeTransport(const {}),
      path: _path,
      cache: cache,
      cacheKey: _key,
    );

    final panel = await store.cachedPanel();

    expect(panel, isNull);
    expect(await cache.read(_key), isNull);
    expect(cache.clearCount, 1);
  });

  // 7. A cached document that is malformed JSON → same: null, cleared, no
  // throw.
  test('a cached document that is malformed JSON: cachedPanel() returns null '
      'and clears the entry, never throws', () async {
    final cache = _FakeSchemaCache()
      ..seed(
        _key,
        const CachedSchema(document: '{not valid json', etag: '"abc"'),
      );
    final store = SchemaCacheStore(
      transport: FakeTransport(const {}),
      path: _path,
      cache: cache,
      cacheKey: _key,
    );

    final panel = await store.cachedPanel();

    expect(panel, isNull);
    expect(await cache.read(_key), isNull);
    expect(cache.clearCount, 1);
  });

  // 8. The host's cache write throws → panel() still returns the panel.
  // Persistence is an optimisation; it must never break a working fetch.
  test('a cache write failure never breaks a working fetch', () async {
    final transport = FakeTransport({_path: _panelJson});
    final store = SchemaCacheStore(
      transport: transport,
      path: _path,
      cache: _ThrowingWriteCache(),
      cacheKey: _key,
    );

    final panel = await store.panel();

    expect(panel.resources.single.key, 'banners');
  });

  // A cache read failure — a closed box, a corrupted entry, any storage I/O
  // error — is the same "persistence is an optimisation" case as the write
  // failure above, and it is the more dangerous of the two: read() fires on
  // every cold start, the most common path in the feature. It must not take
  // a healthy transport down with it.
  test('a cache read failure never breaks a working fetch: panel() still '
      'returns the panel, cachedPanel() returns null', () async {
    final transport = FakeTransport({_path: _panelJson});
    final store = SchemaCacheStore(
      transport: transport,
      path: _path,
      cache: _ThrowingReadCache(),
      cacheKey: _key,
    );

    expect(await store.cachedPanel(), isNull);

    final panel = await store.panel();

    expect(panel.resources.single.key, 'banners');
  });

  // 9. No cacheKey → nothing is read or written even if a cache is supplied
  // (fail-safe).
  test(
    'no cacheKey: nothing is read or written even when a cache is supplied',
    () async {
      final cache = _FakeSchemaCache();
      final transport = FakeTransport({_path: _panelJson});
      final store = SchemaCacheStore(
        transport: transport,
        path: _path,
        cache: cache,
      );

      expect(await store.cachedPanel(), isNull);
      await store.panel();

      expect(cache.readCount, 0);
      expect(cache.writeCount, 0);
    },
  );

  // 10. An empty (or whitespace-only) cacheKey is treated as no key — the
  // `user?.id ?? ''` shape a host can produce when nobody is signed in must
  // never become a shared, unscoped persistent key across users.
  test('an empty or whitespace-only cacheKey is treated as no key: '
      'nothing is read or written', () async {
    for (final key in ['', '   ']) {
      final cache = _FakeSchemaCache();
      final transport = FakeTransport({_path: _panelJson});
      final store = SchemaCacheStore(
        transport: transport,
        path: _path,
        cache: cache,
        cacheKey: key,
      );

      expect(await store.cachedPanel(), isNull);
      await store.panel();

      expect(cache.readCount, 0, reason: 'key "$key" must not be read');
      expect(cache.writeCount, 0, reason: 'key "$key" must not be written');
    }
  });
}
