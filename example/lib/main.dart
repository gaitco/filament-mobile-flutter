import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter/material.dart';

import 'http_filament_transport.dart';

/// A minimal host: index -> list -> record, over real HTTP, no styling of
/// its own — `MaterialPanelStateBuilder`'s default is what's on screen.
///
/// Point it at a live Filament panel running `gait/filament-mobile`:
///
/// ```
/// flutter run -d macos \
///   --dart-define=FILAMENT_BASE_URL=https://your-panel.test \
///   --dart-define=FILAMENT_TOKEN=<a Sanctum bearer token>
/// ```
///
/// An unset or expired/foreign token still boots the app: the panel's own
/// 401 reaches `PanelUnauthenticated`, which is exactly what this example
/// exists to demonstrate.
void main() => runApp(const FilamentMobileExampleApp());

const _baseUrl = String.fromEnvironment('FILAMENT_BASE_URL');
const _token = String.fromEnvironment('FILAMENT_TOKEN');

class FilamentMobileExampleApp extends StatelessWidget {
  const FilamentMobileExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'filament_mobile example',
      home: _baseUrl.isEmpty
          ? const _NotConfigured()
          : PanelHome(baseUrl: _baseUrl, token: _token),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Run with --dart-define=FILAMENT_BASE_URL=https://your-panel.test '
            '--dart-define=FILAMENT_TOKEN=<a bearer token>',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Owns the transport and the panel provider for the session, and wires the
/// package's three screens together — navigation is the host's job, per
/// every screen's `onXTap` doc comment.
class PanelHome extends StatefulWidget {
  const PanelHome({required this.baseUrl, required this.token, super.key});

  final String baseUrl;
  final String token;

  @override
  State<PanelHome> createState() => _PanelHomeState();
}

class _PanelHomeState extends State<PanelHome> {
  late final ResourceDataSource _source = RestResourceDataSource(
    transport: HttpFilamentTransport(
      baseUrl: widget.baseUrl,
      token: () => widget.token,
    ),
  );
  late final PanelProvider _panelProvider = PanelProvider(_source);

  @override
  Widget build(BuildContext context) {
    return PanelIndexScreen(
      provider: _panelProvider,
      onResourceTap: (resource) => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (context) => _resourceList(resource))),
    );
  }

  Widget _resourceList(ResourceSchema resource) {
    return ResourceListScreen(
      provider: ResourceListProvider(source: _source, resource: resource),
      onRecordTap: (record) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ResourceViewScreen(
            provider: ResourceViewProvider(
              source: _source,
              resource: resource,
              id: record.id,
            ),
          ),
        ),
      ),
    );
  }
}
