import 'dart:io';

import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_example/http_filament_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in only: talks to a real backend over the network, so it is skipped
/// unless the environment names one. Neither `flutter test` in CI nor a
/// plain checkout runs this — it is how Task 8 verified the example app's
/// transport against a live panel's backend without adding a network dependency
/// to the package's default suite. Run it with:
///
/// ```
/// FILAMENT_LIVE_BASE_URL=https://your-panel.test \
/// FILAMENT_LIVE_TOKEN=<a real, valid Sanctum bearer token> \
/// FILAMENT_LIVE_BAD_TOKEN=anything-invalid-or-expired \
/// flutter test test/live_pilot_test.dart
/// ```
void main() {
  final baseUrl = Platform.environment['FILAMENT_LIVE_BASE_URL'];
  final token = Platform.environment['FILAMENT_LIVE_TOKEN'];
  final badToken = Platform.environment['FILAMENT_LIVE_BAD_TOKEN'];

  test('a valid token loads the real panel over HTTP', () async {
    if (baseUrl == null || token == null) {
      markTestSkipped(
        'FILAMENT_LIVE_BASE_URL / FILAMENT_LIVE_TOKEN not set — opt-in only.',
      );
      return;
    }

    final source = RestResourceDataSource(
      transport: HttpFilamentTransport(baseUrl: baseUrl, token: () => token),
    );

    final panel = await source.panel();

    expect(panel.resources, isNotEmpty);
  });

  test(
    'an expired or foreign token reaches a 401, not a generic failure',
    () async {
      if (baseUrl == null || badToken == null) {
        markTestSkipped(
          'FILAMENT_LIVE_BASE_URL / FILAMENT_LIVE_BAD_TOKEN not set — opt-in only.',
        );
        return;
      }

      final source = RestResourceDataSource(
        transport: HttpFilamentTransport(
          baseUrl: baseUrl,
          token: () => badToken,
        ),
      );

      await expectLater(
        () => source.panel(),
        throwsA(
          isA<FilamentTransportException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    },
  );
}
