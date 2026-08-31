import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/ports/filament_conditional_transport.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

Map<String, dynamic> get _feed => {
  'data': [
    {
      'id': 'aaa-1',
      'title': 'Order shipped',
      'body': 'Order #7 left the warehouse',
      'status': 'success',
      'color': null,
      'date': '2026-08-31T10:00:00Z',
      'readAt': null,
      'actions': [
        {'label': 'View', 'url': 'https://example.test/orders/7'},
      ],
    },
    {'id': 'aaa-2', 'title': 'Welcome', 'readAt': '2026-08-30T09:00:00Z'},
  ],
  'meta': {'current_page': 1, 'last_page': 3, 'per_page': 20, 'total': 41},
  'unread': 5,
};

RestResourceDataSource _sourceFor(FakeTransport transport) =>
    RestResourceDataSource(transport: transport);

void main() {
  test(
    'notifications() GETs the documented path and parses the page',
    () async {
      final transport = FakeTransport({
        '/api/mobile-panel/notifications': _feed,
      });

      final page = await _sourceFor(transport).notifications(page: 2);

      final call = transport.calls.single;
      expect(call.path, '/api/mobile-panel/notifications');
      expect(call.query, {'page': '2'});

      expect(page.unread, 5);
      expect(page.currentPage, 1);
      expect(page.lastPage, 3);
      expect(page.items, hasLength(2));

      final first = page.items.first;
      expect(first.id, 'aaa-1');
      expect(first.title, 'Order shipped');
      expect(first.status, 'success');
      expect(first.isUnread, isTrue);
      expect(first.date, DateTime.parse('2026-08-31T10:00:00Z'));
      expect(first.actions.single.label, 'View');
      expect(first.actions.single.url, 'https://example.test/orders/7');

      expect(page.items.last.isUnread, isFalse);
    },
  );

  test(
    'malformed rows and action entries are dropped, never thrown on',
    () async {
      final transport = FakeTransport({
        '/api/mobile-panel/notifications': {
          'data': [
            {'id': 'ok', 'title': 'Fine'},
            {'title': 'no id'},
            {'id': 7, 'title': 'non-string id'},
            'not even a map',
            {
              'id': 'ok-2',
              'title': 3,
              'actions': [
                {'label': 'View'},
                {'label': '', 'url': 'https://x'},
                'junk',
                {'label': 'Open', 'url': 'https://example.test'},
              ],
            },
          ],
          'unread': 'five',
          'meta': 'nope',
        },
      });

      final page = await _sourceFor(transport).notifications();

      expect([for (final item in page.items) item.id], ['ok', 'ok-2']);
      expect(page.items.last.title, '', reason: 'wrong-typed title degrades');
      expect(page.items.last.actions.single.label, 'Open');
      expect(page.unread, 0, reason: 'wrong-typed unread reads as 0');
      expect(page.currentPage, 1);
      expect(page.lastPage, 1);
    },
  );

  test('the badge poll reuses its body on a conditional 304', () async {
    final transport = FakeConditionalTransport(
      const {},
      conditionalResponses: {
        '/api/mobile-panel/notifications?page=1': [
          ConditionalResponse(notModified: false, body: _feed, etag: '"feed"'),
          const ConditionalResponse(notModified: true),
        ],
      },
    );
    final source = _sourceFor(transport);

    final first = await source.notifications();
    final second = await source.notifications();

    expect(first.unread, 5);
    expect(second.unread, 5);
    expect(second.items, hasLength(2));
    expect(transport.conditionalCalls.last.etag, '"feed"');
  });

  test('markNotificationRead POSTs the read path and answers unread', () async {
    final transport = FakeTransport(
      const {},
      writes: {
        'POST /api/mobile-panel/notifications/aaa-1/read':
            const FilamentResponse(statusCode: 200, body: {'unread': 4}),
      },
    );

    final unread = await _sourceFor(transport).markNotificationRead('aaa-1');

    expect(unread, 4);
    expect(
      transport.calls.single.path,
      '/api/mobile-panel/notifications/aaa-1/read',
    );
    expect(transport.calls.single.body, isEmpty);
  });

  test('a wrong-typed unread answer reads as 0, never a throw', () async {
    final transport = FakeTransport(
      const {},
      writes: {
        'POST /api/mobile-panel/notifications/read-all': const FilamentResponse(
          statusCode: 200,
          body: {'unread': 'none'},
        ),
      },
    );

    expect(await _sourceFor(transport).markAllNotificationsRead(), 0);
    expect(
      transport.calls.single.path,
      '/api/mobile-panel/notifications/read-all',
    );
  });

  test(
    'deleteNotification and clearNotifications DELETE their paths',
    () async {
      final transport = FakeTransport(
        const {},
        writes: {
          'DELETE /api/mobile-panel/notifications/aaa-1':
              const FilamentResponse(statusCode: 204, body: {}),
          'DELETE /api/mobile-panel/notifications': const FilamentResponse(
            statusCode: 204,
            body: {},
          ),
        },
      );
      final source = _sourceFor(transport);

      await source.deleteNotification('aaa-1');
      await source.clearNotifications();

      expect(transport.calls[0].path, '/api/mobile-panel/notifications/aaa-1');
      expect(transport.calls[1].path, '/api/mobile-panel/notifications');
    },
  );

  test('a non-2xx mutation throws rather than silently no-opping', () async {
    final transport = FakeTransport(
      const {},
      writes: {
        'POST /api/mobile-panel/notifications/gone/read':
            const FilamentResponse(
              statusCode: 404,
              body: {'message': 'Not found'},
            ),
        'DELETE /api/mobile-panel/notifications': const FilamentResponse(
          statusCode: 403,
          body: {'message': 'Forbidden'},
        ),
      },
    );
    final source = _sourceFor(transport);

    await expectLater(
      source.markNotificationRead('gone'),
      throwsA(
        isA<FilamentTransportException>().having(
          (e) => e.message,
          'message',
          'Not found',
        ),
      ),
    );
    await expectLater(
      source.clearNotifications(),
      throwsA(isA<FilamentTransportException>()),
    );
  });
}
