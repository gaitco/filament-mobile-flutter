import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter/material.dart';

import 'demo_transport.dart';

/// Screenshot host: the real screens over [DemoTransport].
///
/// `--dart-define=DEMO_SCREEN=index|list|form` boots straight into the
/// target screen so captures need no tapping.
void main() => runApp(const DemoApp());

const _screen = String.fromEnvironment('DEMO_SCREEN', defaultValue: 'index');

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'filament_mobile demo',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2A3154)),
      home: const _DemoHome(),
    );
  }
}

class _DemoHome extends StatefulWidget {
  const _DemoHome();

  @override
  State<_DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<_DemoHome> {
  late final ResourceDataSource _source = RestResourceDataSource(
    transport: DemoTransport(),
  );
  late final PanelProvider _panel = PanelProvider(_source);

  @override
  Widget build(BuildContext context) {
    if (_screen == 'index') return _index();
    return FutureBuilder<PanelSchema>(
      future: _source.panel(),
      builder: (context, snapshot) {
        final panel = snapshot.data;
        if (panel == null) return const SizedBox.shrink();
        final products = panel.resources.firstWhere((r) => r.key == 'products');
        return _screen == 'form' ? _form(products) : _list(products);
      },
    );
  }

  Widget _index() => PanelIndexScreen(
    provider: _panel,
    onResourceTap: (resource) => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => _list(resource))),
  );

  Widget _list(ResourceSchema resource) => ResourceListScreen(
    provider: ResourceListProvider(source: _source, resource: resource),
    onRecordTap: (record) => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => _view(resource, record))),
  );

  Widget _view(ResourceSchema resource, ResourceRecord record) =>
      ResourceViewScreen(
        provider: ResourceViewProvider(
          source: _source,
          resource: resource,
          id: record.id,
        ),
        onEditTap: (record) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => _form(resource, recordId: record.id),
          ),
        ),
      );

  Widget _form(ResourceSchema resource, {Object? recordId}) =>
      ResourceFormScreen(
        provider: ResourceFormProvider(
          source: _source,
          resource: resource,
          strings: const FilamentStrings(),
          recordId: recordId ?? 1,
        ),
      );
}
