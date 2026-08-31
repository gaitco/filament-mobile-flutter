import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:filament_mobile/state/notifications_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';
import 'support/form_fixtures.dart';

Map<String, dynamic> get _feed => {
  'data': [
    {'id': 'n-1', 'title': 'First', 'readAt': null},
    {'id': 'n-2', 'title': 'Second', 'readAt': '2026-08-30T09:00:00Z'},
  ],
  'meta': {'current_page': 1, 'last_page': 1},
  'unread': 1,
};

NotificationsProvider _providerFor(FakeTransport transport) =>
    NotificationsProvider(RestResourceDataSource(transport: transport));

void main() {
  test('load() fills the feed and the badge count', () async {
    final transport = FakeTransport({'/api/mobile-panel/notifications': _feed});
    final provider = _providerFor(transport);

    await provider.load();

    expect(provider.status, LoadStatus.success);
    expect(provider.items, hasLength(2));
    expect(provider.unread, 1);
  });

  test('a failed load is a failure with the message', () async {
    final transport = FakeTransport({})
      ..errorToThrow = const FilamentTransportException('Server error');
    final provider = _providerFor(transport);

    await provider.load();

    expect(provider.status, LoadStatus.failure);
    expect(provider.errorMessage, 'Server error');
  });

  test('a 401 surfaces as unauthenticated, even on a refresh', () async {
    final transport = FakeTransport({'/api/mobile-panel/notifications': _feed});
    final provider = _providerFor(transport);

    await provider.load();
    transport.errorToThrow = const FilamentTransportException(
      'Unauthenticated.',
      statusCode: 401,
    );
    await provider.refresh();

    expect(provider.status, LoadStatus.failure);
    expect(provider.isUnauthenticated, isTrue);
  });

  test('a timer refresh keeps the loaded feed on transient failure', () async {
    final transport = FakeTransport({'/api/mobile-panel/notifications': _feed});
    final provider = _providerFor(transport);

    await provider.load();
    transport.errorToThrow = const FilamentTransportException('offline');
    await provider.refresh();

    expect(provider.status, LoadStatus.success);
    expect(provider.items, hasLength(2));
    expect(provider.unread, 1);
    expect(provider.errorMessage, 'offline');
  });

  test(
    'a source without the sidecar loads as a benign empty success',
    () async {
      // FakeSource implements ResourceDataSource only — exactly the host data
      // source that predates P21.
      final provider = NotificationsProvider(FakeSource(components: const []));

      await provider.load();

      expect(provider.status, LoadStatus.success);
      expect(provider.items, isEmpty);
      expect(provider.unread, 0);
      expect(provider.errorMessage, isNull);

      expect(await provider.markRead('n-1'), isFalse);
      expect(await provider.clearAll(), isFalse);
    },
  );

  test('markRead applies the server answer to the row and the badge', () async {
    final transport = FakeTransport(
      {'/api/mobile-panel/notifications': _feed},
      writes: {
        'POST /api/mobile-panel/notifications/n-1/read': const FilamentResponse(
          statusCode: 200,
          body: {'unread': 0},
        ),
      },
    );
    final provider = _providerFor(transport);
    await provider.load();

    expect(await provider.markRead('n-1'), isTrue);

    expect(provider.unread, 0);
    expect(provider.items.first.isUnread, isFalse);
    expect(provider.items, hasLength(2), reason: 'the row stays, now read');
  });

  test('markAllRead reads every row and takes the server count', () async {
    final transport = FakeTransport(
      {'/api/mobile-panel/notifications': _feed},
      writes: {
        'POST /api/mobile-panel/notifications/read-all': const FilamentResponse(
          statusCode: 200,
          body: {'unread': 0},
        ),
      },
    );
    final provider = _providerFor(transport);
    await provider.load();

    expect(await provider.markAllRead(), isTrue);

    expect(provider.unread, 0);
    expect(provider.items.every((item) => !item.isUnread), isTrue);
  });

  test('deleteOne removes the row and decrements a lost unread', () async {
    final transport = FakeTransport(
      {'/api/mobile-panel/notifications': _feed},
      writes: {
        'DELETE /api/mobile-panel/notifications/n-1': const FilamentResponse(
          statusCode: 204,
          body: {},
        ),
      },
    );
    final provider = _providerFor(transport);
    await provider.load();

    expect(await provider.deleteOne('n-1'), isTrue);

    expect([for (final item in provider.items) item.id], ['n-2']);
    expect(provider.unread, 0);
  });

  test('clearAll empties the feed and the badge', () async {
    final transport = FakeTransport(
      {'/api/mobile-panel/notifications': _feed},
      writes: {
        'DELETE /api/mobile-panel/notifications': const FilamentResponse(
          statusCode: 204,
          body: {},
        ),
      },
    );
    final provider = _providerFor(transport);
    await provider.load();

    expect(await provider.clearAll(), isTrue);

    expect(provider.items, isEmpty);
    expect(provider.unread, 0);
  });

  test('a failed mutation sets errorMessage and changes no state', () async {
    final transport = FakeTransport(
      {'/api/mobile-panel/notifications': _feed},
      writes: {
        'POST /api/mobile-panel/notifications/n-1/read': const FilamentResponse(
          statusCode: 403,
          body: {'message': 'Forbidden'},
        ),
      },
    );
    final provider = _providerFor(transport);
    await provider.load();

    expect(await provider.markRead('n-1'), isFalse);

    expect(provider.errorMessage, 'Forbidden');
    expect(provider.unread, 1, reason: 'no optimistic state to unwind');
    expect(provider.items.first.isUnread, isTrue);
  });
}
