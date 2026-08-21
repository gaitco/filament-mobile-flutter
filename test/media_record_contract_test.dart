import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/contract_goldens.dart';

/// Contract-golden parsing for the medialibrary record shape
/// (`contract/media-record.json`) — real server output for a resource with
/// one single-file field (`cover`) and one multi-file field (`photos`), each
/// publishing its raw uuid-token value alongside a flat
/// `<field>.__media` sibling. Proves `MediaSet` reads what the server really
/// emits, the same loop `record_payload_contract_test.dart` closes for the
/// plain record shape.
void main() {
  group('media-record.json', () {
    final payload = contractJson('media-record.json');
    final data = payload['data'] as Map<String, dynamic>;

    test('the raw multi-file value is a list of uuid tokens', () {
      expect(data['photos'], isA<List<dynamic>>());
      for (final uuid in data['photos'] as List<dynamic>) {
        expect(uuid, isA<String>());
      }
    });

    test('the raw single-file value is a plain uuid string', () {
      expect(data['cover'], isA<String>());
    });

    test('MediaSet.of parses the multi-file field\'s sibling', () {
      final record = ResourceRecord.fromJson(data, 'id');

      final photos = MediaSet.of(record, 'photos');

      expect(photos, isNotNull);
      expect(photos!.items, hasLength(2));
    });

    test('MediaSet.of parses the single-file field\'s sibling, with a '
        'thumbnail', () {
      final record = ResourceRecord.fromJson(data, 'id');

      final cover = MediaSet.of(record, 'cover');

      expect(cover, isNotNull);
      expect(cover!.items, hasLength(1));
      expect(cover.items.single.thumbUrl, isNotNull);
    });
  });
}
