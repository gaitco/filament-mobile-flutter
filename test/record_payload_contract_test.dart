import 'dart:convert';
import 'dart:io';

import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract-golden parsing for the two endpoint shapes `contract_test.dart`
/// does not cover: the record payload (`contract/record-payload.json`,
/// written by Laravel's RecordSnapshotTest through the real endpoint) and
/// the relation-list envelope (`contract/relation-list.json`,
/// RelationSnapshotTest). Both goldens are real server output; these tests
/// prove the Dart types read them, closing the same loop
/// `laravel_contract_test.dart` closes for `/schema`.
Map<String, dynamic> golden(String name) =>
    jsonDecode(File('../../contract/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('record-payload.json', () {
    final payload = golden('record-payload.json');

    test('parses as a record keyed by id, with the envelope blocks', () {
      final data = payload['data'] as Map<String, dynamic>;

      final record = ResourceRecord.fromJson(
        data,
        'id',
        permissions: payload['permissions'] as Map<String, dynamic>,
        actions: payload['actions'] as List<dynamic>,
      );

      expect(record.id, 1);
      expect(record.can('update'), isTrue);
      expect(record.actions, isEmpty);
    });

    test('carries repeater rows as a list of maps', () {
      // A3: the shape no golden pinned before this slice — a JSON-column
      // repeater's stored rows on the record payload.
      final data = payload['data'] as Map<String, dynamic>;

      final record = ResourceRecord.fromJson(data, 'id');
      final rows = record.get<List>('line_items');

      expect(rows, isNotNull);
      expect(rows, hasLength(2));
      expect(rows![0], isA<Map<String, dynamic>>());
      expect((rows[0] as Map<String, dynamic>)['sku'], 'A-1');
      expect((rows[1] as Map<String, dynamic>)['qty'], 5);
    });

    test('keeps the __rich sibling beside the raw column', () {
      final data = payload['data'] as Map<String, dynamic>;

      expect(data['body_html'], isA<String>());
      expect(data['body_html.__rich'], isA<Map<String, dynamic>>());
    });
  });

  group('relation-list.json', () {
    final envelope = golden('relation-list.json');

    test('parses the meta block', () {
      final meta = PageMeta.fromJson(envelope['meta'] as Map<String, dynamic>);

      expect(meta.total, 2);
      expect(meta.currentPage, 1);
      expect(meta.hasMore, isFalse);
    });

    test('parses rows keyed by the RELATED model\'s recordKey, never an '
        'assumed id', () {
      // The rows carry no `id` — Tag's route key is `name`, on purpose (see
      // the fixture model's docblock). The relation descriptor's `recordKey`
      // is what a client parses by, and this golden is the proof it is not
      // hardcoded `id` anywhere.
      final rows = envelope['data'] as List<dynamic>;

      expect(rows, hasLength(2));

      final first = ResourceRecord.fromJson(
        rows[0] as Map<String, dynamic>,
        'name',
      );

      expect(first.id, 'Red');
      expect(first.get<String>('name'), 'Red');
    });
  });
}
