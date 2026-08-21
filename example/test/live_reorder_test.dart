import 'dart:io';

import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_example/http_filament_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in only, like live_pilot_test.dart: the full P18 reorder cycle
/// against a real panel, through the same provider the list screen drives —
/// enter reorder mode, move the first row to the end, save, prove the server
/// order changed, then restore the original order so the host is left as
/// it was found.
///
/// ```
/// FILAMENT_LIVE_BASE_URL=http://filament-mobile-host.test \
/// FILAMENT_LIVE_TOKEN=<a real Sanctum bearer token> \
/// FILAMENT_LIVE_REORDER_RESOURCE=articles \
/// flutter test test/live_reorder_test.dart
/// ```
void main() {
  final baseUrl = Platform.environment['FILAMENT_LIVE_BASE_URL'];
  final token = Platform.environment['FILAMENT_LIVE_TOKEN'];
  final key =
      Platform.environment['FILAMENT_LIVE_REORDER_RESOURCE'] ?? 'articles';

  test(
    'reorders a live resource through the provider and restores it',
    () async {
      if (baseUrl == null || token == null) {
        markTestSkipped(
          'FILAMENT_LIVE_BASE_URL / FILAMENT_LIVE_TOKEN not set.',
        );
        return;
      }

      final source = RestResourceDataSource(
        transport: HttpFilamentTransport(baseUrl: baseUrl, token: () => token),
      );
      final panel = await source.panel();
      final resource = panel.resource(key);
      expect(resource?.reorder, isNotNull, reason: '$key must be reorderable');

      final provider = ResourceListProvider(
        source: source,
        resource: resource!,
      );
      await provider.enterReorderMode();
      final original = provider.reorderedRecords.map((r) => r.id).toList();
      expect(original.length, greaterThan(2));

      try {
        // Move the first row to the end — the same call the drag handle makes.
        provider.moveRecord(0, original.length - 1);
        await provider.saveReorder();
        expect(provider.errorMessage, isNull);
        expect(provider.isReordering, isFalse);

        final after = (await source.list(
          key,
          reorder: true,
        )).records.map((r) => r.id).toList();
        expect(after.first, original[1]);
        expect(after.last, original.first);
      } finally {
        // Restore: leave the host exactly as found — even when one of the
        // assertions above threw. Without `finally` here, a failed
        // assertion mid-cycle skips straight past the restore and leaves
        // the live host's reorder column permanently mutated for every
        // run after.
        await source.reorder(key, original);
      }

      final restored = (await source.list(
        key,
        reorder: true,
      )).records.map((r) => r.id).toList();
      expect(restored, original);
    },
  );
}
