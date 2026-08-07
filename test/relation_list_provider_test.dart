import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:filament_mobile/state/relation_list_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _relation = RelationDescriptor(
  key: 'tags',
  label: 'Tags',
  card: CardLayout(titleField: 'name'),
);

/// Sibling to `resource_list_provider_test.dart`'s `_ListSource`: `relation()`
/// serves two DISTINCT, real pages so `loadMore()` genuinely appends rather
/// than repeating page one, and records the page argument each call actually
/// carried.
class _RelationSource implements ResourceDataSource {
  _RelationSource({this.error, this.failOnPage});

  final Object? error;

  /// When set, `relation()` throws only once `page` reaches this value —
  /// lets a test succeed on page one and fail on page two.
  final int? failOnPage;

  final List<int> pages = [];

  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
  }) async {
    pages.add(page);
    if (error != null && failOnPage == null) throw error!;
    if (failOnPage != null && page >= failOnPage!) {
      throw error ?? Exception('boom');
    }

    return PaginatedRecords(
      records: [
        ResourceRecord(id: page * 10),
        ResourceRecord(id: page * 10 + 1),
      ],
      meta: PageMeta(currentPage: page, lastPage: 2, perPage: 2, total: 4),
    );
  }

  @override
  Future<PanelSchema> panel() async => throw UnimplementedError();

  @override
  Future<PanelSchema?> cachedPanel() async => null;

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) => throw UnimplementedError();

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) =>
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

  @override
  Future<DashboardData> dashboard() => throw UnimplementedError();

  @override
  Future<UploadResult> uploadFile(
    String resourceKey,
    String field, {
    required List<int> bytes,
    required String filename,
  }) => throw UnimplementedError();
}

RelationListProvider _providerFor(_RelationSource source) =>
    RelationListProvider(
      source: source,
      resourceKey: 'banners',
      id: 7,
      relation: _relation,
    );

void main() {
  test('load() fills records from page one', () async {
    final source = _RelationSource();
    final provider = _providerFor(source);

    await provider.load();

    expect(provider.status, LoadStatus.success);
    expect(provider.records.map((r) => r.id), [10, 11]);
    expect(source.pages, [1]);
  });

  test('loadMore() appends the next page and stops at the last — the '
      'outgoing page number genuinely advances', () async {
    final provider = _providerFor(_RelationSource());

    await provider.load();
    expect(provider.hasMore, isTrue);

    await provider.loadMore();

    expect(provider.records.map((r) => r.id), [10, 11, 20, 21]);
    expect(provider.hasMore, isFalse);
  });

  test('loadMore() is a no-op once there is no more', () async {
    final source = _RelationSource();
    final provider = _providerFor(source);

    await provider.load();
    await provider.loadMore();
    await provider.loadMore();

    expect(source.pages, [1, 2]);
  });

  test('a failure during loadMore keeps the records already shown, and does '
      'not leave isLoadingMore stuck', () async {
    final source = _RelationSource(failOnPage: 2);
    final provider = _providerFor(source);

    await provider.load();
    expect(provider.records, hasLength(2));

    await provider.loadMore();

    expect(provider.records, hasLength(2));
    expect(provider.errorMessage, contains('boom'));
    expect(provider.isLoadingMore, isFalse);
    // The dead-write the P6d Task 8 review caught: `errorMessage` alone is
    // read by nothing once `status` stays `success` — `loadMoreFailed` is
    // the flag `PaginatedCardList`'s trailing row actually renders on.
    expect(provider.loadMoreFailed, isTrue);
  });

  test('a 401 during loadMore reaches the unauthenticated state, not a retry '
      'prompt that can only fail again', () async {
    // Sibling to `ResourceListProvider`'s identical test — the same hole was
    // in both, and the `loadMore` error-surfacing fix had to be applied
    // twice for the same reason.
    final provider = _providerFor(
      _RelationSource(
        failOnPage: 2,
        error: const FilamentTransportException(
          'Unauthenticated.',
          statusCode: 401,
        ),
      ),
    );

    await provider.load();
    await provider.loadMore();

    expect(provider.isUnauthenticated, isTrue);
    expect(provider.status, LoadStatus.failure);
  });

  test('loadMoreFailed clears on refresh() — never left stuck showing a retry '
      'prompt for an error a fresh load has already superseded', () async {
    final provider = _providerFor(_RelationSource(failOnPage: 2));

    await provider.load();
    await provider.loadMore();
    expect(provider.loadMoreFailed, isTrue);

    await provider.refresh();

    expect(provider.loadMoreFailed, isFalse);
  });

  test(
    'a 401 sets isUnauthenticated, distinct from a generic failure',
    () async {
      final provider = _providerFor(
        _RelationSource(
          error: const FilamentTransportException(
            'Unauthenticated.',
            statusCode: 401,
          ),
        ),
      );

      await provider.load();

      expect(provider.status, LoadStatus.failure);
      expect(provider.isUnauthenticated, isTrue);
    },
  );

  test(
    'a 403 surfaces the server\'s own permission message and is NOT '
    'isUnauthenticated — it is a distinct failure, never records: []',
    () async {
      final provider = _providerFor(
        _RelationSource(
          error: const FilamentTransportException(
            'This action is unauthorized.',
            statusCode: 403,
          ),
        ),
      );

      await provider.load();

      expect(provider.status, LoadStatus.failure);
      expect(provider.isUnauthenticated, isFalse);
      expect(provider.errorMessage, 'This action is unauthorized.');
      expect(provider.records, isEmpty);
    },
  );

  test('refresh() reloads from page one', () async {
    final source = _RelationSource();
    final provider = _providerFor(source);

    await provider.load();
    await provider.loadMore();
    await provider.refresh();

    expect(source.pages.last, 1);
    expect(provider.records.map((r) => r.id), [10, 11]);
  });
}
