import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:filament_mobile/state/resource_view_provider.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// A settable source, so a test can change what the next `record()` call
/// returns (or throws) mid-test to simulate a refresh landing new data or
/// failing outright.
///
/// Note: the mutable slot is named [nextRecord], not `record` — the interface
/// method is already called `record(resourceKey, id)`, and Dart forbids a
/// field and a method sharing a name on the same class. The constructor still
/// accepts a `record:` argument for a call site that reads naturally.
class FakeSource implements ResourceDataSource {
  FakeSource({required ResourceRecord record, this.error})
    : nextRecord = record;

  ResourceRecord nextRecord;
  Object? error;

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async {
    if (error != null) throw error!;
    return nextRecord;
  }

  @override
  Future<PanelSchema> panel() async => throw UnimplementedError();

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async => throw UnimplementedError();

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

ResourceSchema get bannersSchema => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'Banner', 'plural': 'Banners'},
  'recordKey': 'id',
  'infolist': [
    {'type': 'text_entry', 'name': 'name', 'label': 'Name'},
  ],
}, 'r');

ResourceRecord recordWith({required String name}) =>
    ResourceRecord.fromJson({'id': 7, 'name': name}, 'id');

void main() {
  group('ResourceViewProvider.load(keepPrevious:)', () {
    test('a refresh keeps the old record visible while loading', () async {
      // Without this the screen blanks to a skeleton on every refresh, which is
      // why P1 removed pull-to-refresh rather than ship a flicker.
      final source = FakeSource(record: recordWith(name: 'Original'));
      final provider = ResourceViewProvider(
        source: source,
        resource: bannersSchema,
        id: 7,
      );

      await provider.load();
      expect(provider.record?.get<String>('name'), 'Original');

      source.nextRecord = recordWith(name: 'Updated');
      final pending = provider.load(keepPrevious: true);

      expect(provider.status, LoadStatus.loading);
      expect(
        provider.record?.get<String>('name'),
        'Original',
        reason: 'the old record must stay visible while the new one loads',
      );

      await pending;
      expect(provider.record?.get<String>('name'), 'Updated');
    });

    test('a failed refresh keeps the old record rather than blanking', () async {
      // A refresh that fails must not cost the user the data they were reading.
      final source = FakeSource(record: recordWith(name: 'Original'));
      final provider = ResourceViewProvider(
        source: source,
        resource: bannersSchema,
        id: 7,
      );

      await provider.load();
      source.error = const FilamentTransportException('لا يوجد اتصال');
      await provider.load(keepPrevious: true);

      expect(provider.status, LoadStatus.failure);
      expect(provider.record?.get<String>('name'), 'Original');
      expect(provider.errorMessage, 'لا يوجد اتصال');
    });

    test(
      'a first load still clears, so no stale record leaks between screens',
      () async {
        final source = FakeSource(record: recordWith(name: 'Original'));
        final provider = ResourceViewProvider(
          source: source,
          resource: bannersSchema,
          id: 7,
        );

        await provider.load();
        final pending = provider.load();

        expect(provider.record, isNull);
        await pending;
      },
    );
  });
}
