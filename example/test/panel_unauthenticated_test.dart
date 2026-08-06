import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_example/http_filament_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The whole chain the example app wires together — `HttpFilamentTransport`
/// through `RestResourceDataSource` through `PanelProvider` through the
/// package's real `PanelIndexScreen` — driven against a `MockClient` that
/// answers exactly what a live panel answers for an expired or foreign
/// token: HTTP 401. No network, so it runs in CI, but every class in the
/// chain except the transport's underlying `http.Client` is the same one
/// the live pilot exercised against a real backend.
void main() {
  testWidgets('an expired or foreign token reaches PanelUnauthenticated, '
      'not a generic PanelFailure', (tester) async {
    final source = RestResourceDataSource(
      transport: HttpFilamentTransport(
        baseUrl: 'https://panel.test',
        token: () => 'expired-or-foreign-token',
        client: MockClient(
          (request) async =>
              http.Response('{"message":"Unauthenticated."}', 401),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PanelIndexScreen(
          provider: PanelProvider(source),
          onResourceTap: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('panel.unauthenticated')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
