import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

void main() {
  group('uploadFile', () {
    test('a transport lacking FilamentUploadTransport fails with an actionable '
        'message, never throws', () async {
      final source = RestResourceDataSource(transport: FakeTransport({}));

      final result = await source.uploadFile(
        'banners',
        'photo',
        bytes: const [1, 2, 3],
        filename: 'photo.png',
      );

      expect(result, isA<UploadFailed>());
      final failure = result as UploadFailed;
      expect(failure.message, contains('FilamentUploadTransport'));
      // No response was ever made, so there is no status to route on — the
      // provider's routing treats null the same as any non-422.
      expect(failure.statusCode, isNull);
    });

    test('a 200 with a path yields UploadSuccess with that path', () async {
      final transport = FakeUploadTransport(
        {},
        uploadResponse: const FilamentResponse(
          statusCode: 200,
          body: {'path': 'x/y.png'},
        ),
      );
      final source = RestResourceDataSource(transport: transport);

      final result = await source.uploadFile(
        'banners',
        'photo',
        bytes: const [1, 2, 3],
        filename: 'photo.png',
      );

      expect(result, isA<UploadSuccess>());
      expect((result as UploadSuccess).path, 'x/y.png');
      expect(transport.lastUpload?.path, '/api/mobile-panel/banners/upload');
      expect(transport.lastUpload?.field, 'photo');
      expect(transport.lastUpload?.filename, 'photo.png');
    });

    test('a 422 with a message yields UploadFailed carrying it', () async {
      final transport = FakeUploadTransport(
        {},
        uploadResponse: const FilamentResponse(
          statusCode: 422,
          body: {'message': 'The photo failed to upload.'},
        ),
      );
      final source = RestResourceDataSource(transport: transport);

      final result = await source.uploadFile(
        'banners',
        'photo',
        bytes: const [1, 2, 3],
        filename: 'photo.png',
      );

      expect(result, isA<UploadFailed>());
      final failure = result as UploadFailed;
      expect(failure.message, 'The photo failed to upload.');
      // The field-vs-banner routing in ResourceFormProvider.uploadFile()
      // reads this: a literal 422 is this field's own refusal.
      expect(failure.statusCode, 422);
    });

    test('a bodyless 403 yields UploadFailed carrying that status', () async {
      final transport = FakeUploadTransport(
        {},
        uploadResponse: const FilamentResponse(statusCode: 403, body: {}),
      );
      final source = RestResourceDataSource(transport: transport);

      final result = await source.uploadFile(
        'banners',
        'photo',
        bytes: const [1, 2, 3],
        filename: 'photo.png',
      );

      expect(result, isA<UploadFailed>());
      final failure = result as UploadFailed;
      expect(failure.message, isNull);
      // Not a 422, so ResourceFormProvider.uploadFile() must route this to
      // the form banner, not the field.
      expect(failure.statusCode, 403);
    });

    test('a transport throw (offline) yields UploadFailed(messageOf(e)), the '
        'same contract every other write has', () async {
      final transport = FakeUploadTransport(
        {},
        uploadError: const FilamentTransportException('No connection.'),
      );
      final source = RestResourceDataSource(transport: transport);

      final result = await source.uploadFile(
        'banners',
        'photo',
        bytes: const [1, 2, 3],
        filename: 'photo.png',
      );

      expect(result, isA<UploadFailed>());
      final failure = result as UploadFailed;
      expect(failure.message, 'No connection.');
      expect(failure.statusCode, isNull);
    });
  });
}
