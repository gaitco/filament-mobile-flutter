import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:filament_mobile/state/panel_provider.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubSource implements ResourceDataSource {
  _StubSource({this.panelResult, this.error});

  final PanelSchema? panelResult;
  final Object? error;
  int panelCalls = 0;

  @override
  Future<PanelSchema> panel() async {
    panelCalls++;
    if (error != null) throw error!;
    return panelResult!;
  }

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async => throw UnimplementedError();

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async =>
      throw UnimplementedError();

  @override
  Future<WriteResult> create(String resourceKey, Map<String, dynamic> values) =>
      throw UnimplementedError();

  @override
  Future<WriteResult> update(
    String resourceKey,
    Object id,
    Map<String, dynamic> values,
  ) => throw UnimplementedError();

  @override
  Future<WriteResult> destroy(String resourceKey, Object id) =>
      throw UnimplementedError();

  @override
  Future<ActionResult> runAction(
    String resourceKey,
    Object id,
    String action,
  ) => throw UnimplementedError();

  @override
  Future<OptionsPage> options(
    String resourceKey, {

    required String field,

    Object? recordId,

    required Map<String, dynamic> values,

    required String query,
  }) => throw UnimplementedError();

  @override
  Future<List<SchemaComponent>> state(
    String resourceKey, {
    Object? recordId,
    required Map<String, dynamic> values,
    required String changed,
  }) => throw UnimplementedError();
}

PanelSchema get _panel => PanelSchema.fromJson(const {
  'version': 1,
  'panel': {'id': 'mobile', 'title': 'لوحة التحكم'},
  'resources': [],
});

void main() {
  test('starts in initial', () {
    expect(PanelProvider(_StubSource()).status, LoadStatus.initial);
  });

  test('load() moves through loading to success', () async {
    final provider = PanelProvider(_StubSource(panelResult: _panel));
    final seen = <LoadStatus>[];
    provider.addListener(() => seen.add(provider.status));

    await provider.load();

    expect(seen, [LoadStatus.loading, LoadStatus.success]);
    expect(provider.panel!.title, 'لوحة التحكم');
    expect(provider.errorMessage, isNull);
  });

  test('a transport failure becomes failure with a message', () async {
    final provider = PanelProvider(
      _StubSource(error: Exception('تعذّر الاتصال')),
    );

    await provider.load();

    expect(provider.status, LoadStatus.failure);
    expect(provider.errorMessage, contains('تعذّر الاتصال'));
    expect(provider.needsAppUpdate, isFalse);
  });

  test('an unsupported schema version sets needsAppUpdate', () async {
    final provider = PanelProvider(
      _StubSource(
        error: const UnsupportedSchemaVersionException(found: 2, supported: 1),
      ),
    );

    await provider.load();

    expect(provider.status, LoadStatus.failure);
    expect(provider.needsAppUpdate, isTrue);
  });

  test('load() can be retried after a failure', () async {
    final source = _StubSource(error: Exception('boom'));
    final provider = PanelProvider(source);

    await provider.load();
    expect(provider.status, LoadStatus.failure);

    await provider.load();
    expect(source.panelCalls, 2);
  });
}
