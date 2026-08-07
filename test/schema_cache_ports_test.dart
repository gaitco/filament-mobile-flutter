// Deliberately imports ONLY the barrel — see public_api_test.dart for why:
// P6a shipped a type the barrel didn't export, and every test in the package
// still passed because every test imported by path.
import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter_test/flutter_test.dart';

/// A host implementing both ports with the bare minimum — nothing else on
/// either interface to satisfy.
class _FakeConditionalTransport implements FilamentConditionalTransport {
  @override
  Future<ConditionalResponse> getConditional(
    String path, {
    String? etag,
  }) async {
    return const ConditionalResponse(notModified: true);
  }
}

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

void main() {
  test('a notModified ConditionalResponse carries a null body', () {
    const response = ConditionalResponse(notModified: true, etag: '"abc"');
    expect(response.notModified, isTrue);
    expect(response.body, isNull);
  });

  test('a 200 ConditionalResponse carries a body and is not notModified', () {
    const response = ConditionalResponse(
      notModified: false,
      body: {'version': 1},
      etag: '"def"',
    );
    expect(response.notModified, isFalse);
    expect(response.body, {'version': 1});
  });

  test('CachedSchema stores the document string and an optional etag', () {
    const cached = CachedSchema(document: '{"version":1}', etag: '"abc"');
    expect(cached.document, '{"version":1}');
    expect(cached.etag, '"abc"');
  });

  test('CachedSchema.etag defaults to null', () {
    const cached = CachedSchema(document: '{"version":1}');
    expect(cached.etag, isNull);
  });

  test('a host can name both port types through the package barrel', () {
    // Both are optional and abstract — this package never instantiates
    // either — so naming the type is the whole test: it fails to compile if
    // the barrel stops exporting it.
    FilamentConditionalTransport? conditionalTransport;
    FilamentSchemaCache? schemaCache;
    expect(conditionalTransport, isNull);
    expect(schemaCache, isNull);
  });

  test(
    'a host can implement FilamentConditionalTransport with only getConditional',
    () async {
      final transport = _FakeConditionalTransport();
      final response = await transport.getConditional(
        '/api/schema',
        etag: '"abc"',
      );
      expect(response.notModified, isTrue);
    },
  );

  test(
    'a host can implement FilamentSchemaCache with only read/write/clear',
    () async {
      final cache = _FakeSchemaCache();
      const value = CachedSchema(document: '{"version":1}', etag: '"abc"');

      await cache.write('user:1', value);
      expect((await cache.read('user:1'))?.document, '{"version":1}');

      await cache.clear('user:1');
      expect(await cache.read('user:1'), isNull);
    },
  );
}
