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

  group('getConditional()', () {
    test('sends If-None-Match only when an etag is given', () async {
      String? sentHeader;
      final transport = HttpFilamentTransport(
        baseUrl: 'https://panel.test',
        token: () => 'valid-token',
        client: MockClient((request) async {
          sentHeader = request.headers['If-None-Match'];
          return http.Response(jsonEncode({'version': 1}), 200);
        }),
      );

      await transport.getConditional('/api/schema');

      expect(sentHeader, isNull);

      await transport.getConditional('/api/schema', etag: 'W/"abc"');

      expect(sentHeader, 'W/"abc"');
    });

    test('a 304 comes back as notModified: true, not a throw — the one thing '
        'get() cannot do', () async {
      final transport = HttpFilamentTransport(
        baseUrl: 'https://panel.test',
        token: () => 'valid-token',
        client: MockClient(
          (request) async =>
              http.Response('', 304, headers: {'etag': 'W/"abc"'}),
        ),
      );

      final response = await transport.getConditional(
        '/api/schema',
        etag: 'W/"abc"',
      );

      expect(response.notModified, isTrue);
      expect(response.body, isNull);
      expect(response.etag, 'W/"abc"');
    });

    test('a 200 decodes the body and carries the new etag', () async {
      final transport = HttpFilamentTransport(
        baseUrl: 'https://panel.test',
        token: () => 'valid-token',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'version': 1}),
            200,
            headers: {'etag': 'W/"def"'},
          ),
        ),
      );

      final response = await transport.getConditional('/api/schema');

      expect(response.notModified, isFalse);
      expect(response.body, {'version': 1});
      expect(response.etag, 'W/"def"');
    });

    test('a 401 throws FilamentTransportException, same as get()', () async {
      final transport = HttpFilamentTransport(
        baseUrl: 'https://panel.test',
        token: () => 'expired-token',
        client: MockClient(
          (request) async =>
              http.Response(jsonEncode({'message': 'Unauthenticated.'}), 401),
        ),
      );

      await expectLater(
        () => transport.getConditional('/api/schema'),
        throwsA(
          isA<FilamentTransportException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Unauthenticated.'),
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

  group('upload()', () {
    test('sends the bytes and field name as multipart parts', () async {
      final transport = HttpFilamentTransport(
        baseUrl: 'https://panel.test',
        token: () => 'valid-token',
        client: MockClient.streaming((request, bodyStream) async {
          expect(request, isA<http.MultipartRequest>());
          final multipart = request as http.MultipartRequest;
          expect(
            multipart.url.toString(),
            'https://panel.test/api/products/upload',
          );
          expect(multipart.headers['Authorization'], 'Bearer valid-token');
          expect(multipart.fields['field'], 'photo');
          expect(multipart.files, hasLength(1));
          expect(multipart.files.single.field, 'file');
          expect(multipart.files.single.filename, 'photo.png');

          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'path': 'x/photo.png'}))),
            200,
          );
        }),
      );

      final response = await transport.upload(
        '/api/products/upload',
        bytes: [1, 2, 3],
        filename: 'photo.png',
        field: 'photo',
      );

      expect(response.statusCode, 200);
      expect(response.body['path'], 'x/photo.png');
    });

    test('never throws on a non-2xx — the write asymmetry', () async {
      final transport = HttpFilamentTransport(
        baseUrl: 'https://panel.test',
        token: () => 't',
        client: MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(jsonEncode({'message': 'File is too large.'})),
            ),
            422,
          );
        }),
      );

      final response = await transport.upload(
        '/api/products/upload',
        bytes: [1, 2, 3],
        filename: 'photo.png',
      );

      expect(response.statusCode, 422);
      expect(response.body['message'], 'File is too large.');
    });
  });
}
