import 'dart:convert';

import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_example/http_filament_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// No network in this file — every response is synthesised by `MockClient`,
/// so these run in CI exactly like the package's own tests.
void main() {
  group('get()', () {
    test('decodes a 200 body', () async {
      final transport = HttpFilamentTransport(
        baseUrl: 'https://panel.test',
        token: () => 'valid-token',
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://panel.test/api/schema');
          expect(request.headers['Authorization'], 'Bearer valid-token');
          return http.Response(jsonEncode({'version': 1}), 200);
        }),
      );

      final body = await transport.get('/api/schema');

      expect(body, {'version': 1});
    });

    test('throws FilamentTransportException(statusCode: 401) on a 401 — '
        'the one line the port doc comment asks a host to add', () async {
      final transport = HttpFilamentTransport(
        baseUrl: 'https://panel.test',
        token: () => 'expired-or-foreign-token',
        client: MockClient(
          (request) async =>
              http.Response(jsonEncode({'message': 'Unauthenticated.'}), 401),
        ),
      );

      await expectLater(
        () => transport.get('/api/schema'),
        throwsA(
          isA<FilamentTransportException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Unauthenticated.'),
        ),
      );
    });

    test('a non-401 failure carries its own status, not 401', () async {
      final transport = HttpFilamentTransport(
        baseUrl: 'https://panel.test',
        token: () => 'valid-token',
        client: MockClient((request) async => http.Response('', 500)),
      );

      await expectLater(
        () => transport.get('/api/schema'),
        throwsA(
          isA<FilamentTransportException>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });
  });

  group('post()/put()/delete()', () {
    test('never throws on a non-2xx — the write asymmetry', () async {
      final transport = HttpFilamentTransport(
        baseUrl: 'https://panel.test',
        token: () => 't',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'errors': {
                'name': ['required'],
              },
            }),
            422,
          ),
        ),
      );

      final response = await transport.post('/api/banners', {});

      expect(response.statusCode, 422);
      expect(response.body['errors'], isNotNull);
    });

    test(
      'delete() decodes an empty 204 body as {}, not a parse failure',
      () async {
        final transport = HttpFilamentTransport(
          baseUrl: 'https://panel.test',
          token: () => 't',
          client: MockClient((request) async => http.Response('', 204)),
        );

        final response = await transport.delete('/api/banners/1');

        expect(response.statusCode, 204);
        expect(response.body, <String, dynamic>{});
      },
    );
  });
}
