import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:filament_mobile/state/panel_provider.dart';
import 'package:filament_mobile/state/resource_form_provider.dart';
import 'package:filament_mobile/state/resource_list_provider.dart';
import 'package:filament_mobile/state/resource_view_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Throws [error] from whichever read call the provider under test makes;
/// the other methods are never exercised by these tests.
class FakeSource implements ResourceDataSource {
  FakeSource({this.error});

  final Object? error;

  @override
  Future<PanelSchema> panel() async => throw error!;

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async => throw error!;

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async =>
      throw error!;

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

ResourceSchema get _resource => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'Banner', 'plural': 'Banners'},
  'recordKey': 'id',
}, 'r');

void main() {
  group('PanelProvider', () {
    test('a 401 on /schema becomes unauthenticated, not a failure', () async {
      final provider = PanelProvider(
        FakeSource(
          error: const FilamentTransportException(
            'signed out',
            statusCode: 401,
          ),
        ),
      );

      await provider.load();

      expect(provider.isUnauthenticated, isTrue);
    });

    test('a 500 stays an ordinary failure', () async {
      // The counter-test. A provider that treated every error as signed-out
      // would pass the test above while being useless.
      final provider = PanelProvider(
        FakeSource(
          error: const FilamentTransportException('boom', statusCode: 500),
        ),
      );

      await provider.load();

      expect(provider.isUnauthenticated, isFalse);
      expect(provider.status, LoadStatus.failure);
    });

    test('an exception with no status stays an ordinary failure', () async {
      // The advisory field's fallback, and the reason option (a) is acceptable:
      // a host that never sets it keeps today's behaviour.
      final provider = PanelProvider(
        FakeSource(error: const FilamentTransportException('offline')),
      );

      await provider.load();

      expect(provider.isUnauthenticated, isFalse);
    });
  });

  group('ResourceListProvider', () {
    test('a 401 on the list becomes unauthenticated, not a failure', () async {
      final provider = ResourceListProvider(
        source: FakeSource(
          error: const FilamentTransportException(
            'signed out',
            statusCode: 401,
          ),
        ),
        resource: _resource,
      );

      await provider.load();

      expect(provider.isUnauthenticated, isTrue);
    });

    test('a 500 stays an ordinary failure', () async {
      final provider = ResourceListProvider(
        source: FakeSource(
          error: const FilamentTransportException('boom', statusCode: 500),
        ),
        resource: _resource,
      );

      await provider.load();

      expect(provider.isUnauthenticated, isFalse);
      expect(provider.status, LoadStatus.failure);
    });

    test('an exception with no status stays an ordinary failure', () async {
      final provider = ResourceListProvider(
        source: FakeSource(error: const FilamentTransportException('offline')),
        resource: _resource,
      );

      await provider.load();

      expect(provider.isUnauthenticated, isFalse);
    });
  });

  group('ResourceViewProvider', () {
    test(
      'a 401 on the record becomes unauthenticated, not a failure',
      () async {
        final provider = ResourceViewProvider(
          source: FakeSource(
            error: const FilamentTransportException(
              'signed out',
              statusCode: 401,
            ),
          ),
          resource: _resource,
          id: 7,
        );

        await provider.load();

        expect(provider.isUnauthenticated, isTrue);
      },
    );

    test('a 500 stays an ordinary failure', () async {
      final provider = ResourceViewProvider(
        source: FakeSource(
          error: const FilamentTransportException('boom', statusCode: 500),
        ),
        resource: _resource,
        id: 7,
      );

      await provider.load();

      expect(provider.isUnauthenticated, isFalse);
      expect(provider.status, LoadStatus.failure);
    });

    test('an exception with no status stays an ordinary failure', () async {
      final provider = ResourceViewProvider(
        source: FakeSource(error: const FilamentTransportException('offline')),
        resource: _resource,
        id: 7,
      );

      await provider.load();

      expect(provider.isUnauthenticated, isFalse);
    });
  });

  group('ResourceFormProvider', () {
    // Edit mode only: recordId != null routes load() through _source.record(),
    // the same read path ResourceViewProvider exercises above. Create mode has
    // no read to fail on load.
    test(
      'a 401 loading the record for edit becomes unauthenticated, not a failure',
      () async {
        final provider = ResourceFormProvider(
          source: FakeSource(
            error: const FilamentTransportException(
              'signed out',
              statusCode: 401,
            ),
          ),
          resource: _resource,
          strings: const FilamentStrings(),
          recordId: 7,
        );

        await provider.load();

        expect(provider.isUnauthenticated, isTrue);
      },
    );

    test('a 500 stays an ordinary failure', () async {
      final provider = ResourceFormProvider(
        source: FakeSource(
          error: const FilamentTransportException('boom', statusCode: 500),
        ),
        resource: _resource,
        strings: const FilamentStrings(),
        recordId: 7,
      );

      await provider.load();

      expect(provider.isUnauthenticated, isFalse);
      expect(provider.status, LoadStatus.failure);
    });

    test('an exception with no status stays an ordinary failure', () async {
      final provider = ResourceFormProvider(
        source: FakeSource(error: const FilamentTransportException('offline')),
        resource: _resource,
        strings: const FilamentStrings(),
        recordId: 7,
      );

      await provider.load();

      expect(provider.isUnauthenticated, isFalse);
    });
  });
}
