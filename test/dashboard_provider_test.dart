import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/state/dashboard_provider.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transport.dart';

void main() {
  test('a panel without a dashboard endpoint is an empty dashboard', () async {
    // A 404 on /dashboard is "this panel serves no dashboard" — a read-only
    // host (gait/nova-mobile's first slice) or a Filament panel with the
    // dashboard disabled — not a failure to show the user. Every other
    // status stays an error.
    final transport = FakeTransport({})
      ..errorToThrow = const FilamentTransportException(
        'No resource [dashboard].',
        statusCode: 404,
      );
    final provider = DashboardProvider(
      RestResourceDataSource(transport: transport),
    );

    await provider.load();

    expect(provider.status, LoadStatus.success);
    expect(provider.data?.widgets, isEmpty);
    expect(provider.errorMessage, isNull);
  });

  test('a 500 on the dashboard is still a failure', () async {
    final transport = FakeTransport({})
      ..errorToThrow = const FilamentTransportException(
        'Server error',
        statusCode: 500,
      );
    final provider = DashboardProvider(
      RestResourceDataSource(transport: transport),
    );

    await provider.load();

    expect(provider.status, LoadStatus.failure);
    expect(provider.errorMessage, 'Server error');
  });
}
