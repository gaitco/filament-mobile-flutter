import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter/material.dart';

import 'demo_transport.dart';

/// Screenshot host: the real screens over [DemoTransport].
///
/// `--dart-define=DEMO_SCREEN=index|list|form|dashboard` boots straight into
/// the target screen so captures need no tapping.
void main() => runApp(const DemoApp());

const _screen = String.fromEnvironment('DEMO_SCREEN', defaultValue: 'index');

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'filament_mobile demo',
      debugShowCheckedModeBanner: false,
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
  late final DashboardProvider _dashboard = DashboardProvider(_source);

  @override
  Widget build(BuildContext context) {
    if (_screen == 'index') return _index();
    // No chartBuilder: the demo ships no charting dependency, so the chart
    // card renders its honest "no chart renderer supplied" fallback — see
    // the package README's Dashboard section for wiring a real one.
    if (_screen == 'dashboard') return DashboardScreen(provider: _dashboard);
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
        // `onLinkTap` makes a rich-text link tappable — this package takes
        // no URL-launcher dependency, so opening it is entirely the host's
        // call. This demo has no such dependency either, so it echoes the
        // href instead of opening it; a host wiring a real `url_launcher`
        // call goes here.
        registry: EntryRegistry.defaults(
          onLinkTap: (href) => ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Link tapped: $href'))),
        ),
        onEditTap: (record) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => _form(resource, recordId: record.id),
          ),
        ),
        onSeeAllTap: (relation, recordId) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => RelationListScreen(
              provider: RelationListProvider(
                source: _source,
                resourceKey: resource.key,
                id: recordId,
                relation: relation,
              ),
            ),
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
        filePicker: _pickFile,
      );

  // A real host wires image_picker or file_picker here. The demo ships no
  // such dependency, so it returns a small synthetic byte list under a fixed
  // filename — enough to exercise the upload wiring, not to pick a real file.
  Future<PickedFile?> _pickFile(SchemaComponent field) async =>
      const PickedFile(bytes: [1, 2, 3, 4], filename: 'demo-photo.png');
}
