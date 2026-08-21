import 'dart:io';

import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_example/http_filament_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in only, like live_pilot_test.dart — but against a Laravel NOVA host
/// running gait/nova-mobile, which mounts the identical contract under its
/// own prefix. This is the end-to-end proof that the client needs no Nova
/// knowledge: the same data source browses panel → list → search → detail.
///
/// ```
/// NOVA_LIVE_BASE_URL=http://127.0.0.1:8765 \
/// NOVA_LIVE_TOKEN=<a real Sanctum bearer token> \
/// NOVA_LIVE_RESOURCE=courses \
/// flutter test test/live_nova_test.dart
/// ```
void main() {
  final baseUrl = Platform.environment['NOVA_LIVE_BASE_URL'];
  final token = Platform.environment['NOVA_LIVE_TOKEN'];
  final resourceKey = Platform.environment['NOVA_LIVE_RESOURCE'] ?? 'courses';

  test('browses a Nova host read-only: panel, list, search, detail', () async {
    if (baseUrl == null || token == null) {
      markTestSkipped('NOVA_LIVE_BASE_URL / NOVA_LIVE_TOKEN not set.');
      return;
    }

    final source = RestResourceDataSource(
      transport: HttpFilamentTransport(baseUrl: baseUrl, token: () => token),
      prefix: '/api/nova-mobile',
    );

    final panel = await source.panel();
    final resource = panel.resource(resourceKey);
    expect(resource, isNotNull, reason: '$resourceKey must be opted in');
    expect(resource!.infolist, isNotEmpty);

    final page = await source.list(resourceKey);
    expect(page.meta.total, greaterThan(0));
    expect(page.records, isNotEmpty);
    // The card whitelist: a list row carries the card's fields, nothing else.
    final row = page.records.first;
    expect(row.attributes.keys, containsAll(['name', 'type']));
    expect(row.attributes.containsKey('description'), isFalse);

    final searched = await source.list(resourceKey, search: 'zzzzqq-no-match');
    expect(searched.meta.total, 0);

    final record = await source.record(resourceKey, row.id);
    expect(record.attributes['name'], row.attributes['name']);
    // Detail widens to the infolist: a field the card never showed is here.
    expect(record.attributes.containsKey('description'), isTrue);
  });
}
