// P18 Task 6, Step 1: `list(reorder: true)` hits `?reorder=1` with no
// sort/direction, and `reorder()` POSTs the order body and throws on non-2xx
// — the same never-a-silent-no-op contract `state()`/`options()` already use.

import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

Map<String, dynamic> get _panelJson => {
  'version': 1,
  'panel': {'id': 'mobile', 'title': 'لوحة التحكم'},
  'resources': [
    {
      'key': 'slides',
      'labels': {'singular': 'شريحة', 'plural': 'الشرائح'},
      'recordKey': 'id',
      'card': {
        'title': {'field': 'name'},
      },
      'reorder': {'column': 'position', 'direction': 'asc'},
    },
  ],
};

RestResourceDataSource sourceFor(FakeTransport transport) =>
    RestResourceDataSource(transport: transport);

void main() {
  test(
    'list(reorder: true) sends `reorder=1` and omits sort/direction',
    () async {
      final transport = FakeTransport({
        '/api/mobile-panel/schema': _panelJson,
        '/api/mobile-panel/slides': {
          'data': [
            {'id': 1, 'name': 'A'},
            {'id': 2, 'name': 'B'},
          ],
          'meta': {
            'current_page': 1,
            'last_page': 1,
            'per_page': 2,
            'total': 2,
          },
        },
      });

      final page = await sourceFor(
        transport,
      ).list('slides', sort: 'name', direction: 'desc', reorder: true);

      expect(page.records, hasLength(2));
      final call = transport.calls.last;
      expect(call.path, '/api/mobile-panel/slides');
      expect(call.query!['reorder'], '1');
      expect(call.query!.containsKey('sort'), isFalse);
      expect(call.query!.containsKey('direction'), isFalse);
    },
  );

  test('list() with reorder omitted (or false) sends no `reorder` param, sort '
      'and direction intact', () async {
    final transport = FakeTransport({
      '/api/mobile-panel/schema': _panelJson,
      '/api/mobile-panel/slides': {
        'data': <Map<String, dynamic>>[],
        'meta': {'current_page': 1, 'last_page': 1, 'per_page': 20, 'total': 0},
      },
    });

    await sourceFor(transport).list('slides', sort: 'name', direction: 'asc');

    final call = transport.calls.last;
    expect(call.query!.containsKey('reorder'), isFalse);
    expect(call.query!['sort'], 'name');
    expect(call.query!['direction'], 'asc');
  });

  test('reorder() POSTs {"order": ids} to `{resource}/reorder`', () async {
    final transport = FakeTransport(
      const {},
      writes: const {
        'POST /api/mobile-panel/slides/reorder': FilamentResponse(
          statusCode: 200,
          body: {'message': 'Reordered.'},
        ),
      },
    );

    await sourceFor(transport).reorder('slides', [3, 1, 2]);

    expect(transport.calls.single.path, '/api/mobile-panel/slides/reorder');
    expect(transport.calls.single.body, {
      'order': [3, 1, 2],
    });
  });

  test('reorder() throws FilamentTransportException on a non-2xx', () async {
    final transport = FakeTransport(
      const {},
      writes: const {
        'POST /api/mobile-panel/slides/reorder': FilamentResponse(
          statusCode: 422,
          body: {'message': 'Unknown record in order.'},
        ),
      },
    );

    await expectLater(
      sourceFor(transport).reorder('slides', [1]),
      throwsA(
        isA<FilamentTransportException>().having(
          (e) => e.message,
          'message',
          'Unknown record in order.',
        ),
      ),
    );
  });
}
