import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:filament_mobile/state/resource_list_provider.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:flutter_test/flutter_test.dart';

class _ListSource implements ResourceDataSource {
  _ListSource({this.error, this.failOnPage});

  final Object? error;

  /// When set, `list()` throws only once `page` reaches this value —
  /// lets a test succeed on page one and fail on page two.
  final int? failOnPage;
  final List<({int page, String? search, String? sort, String? direction})>
  calls = [];

  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async => throw UnimplementedError();

  @override
  Future<WriteResult> createRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Map<String, dynamic> values,
  ) => throw UnimplementedError();

  @override
  Future<WriteResult> updateRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
    Map<String, dynamic> values,
  ) => throw UnimplementedError();

  @override
  Future<WriteResult> deleteRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
  ) => throw UnimplementedError();

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async {
    calls.add((page: page, search: search, sort: sort, direction: direction));
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

ResourceSchema get _resource => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'لافتة', 'plural': 'اللافتات'},
  'search': {'enabled': true},
  'sorts': [
    {
      'key': 'created_at',
      'label': 'الأحدث',
      'direction': 'desc',
      'default': true,
    },
    {'key': 'name', 'label': 'الاسم'},
  ],
}, 'r');

ResourceListProvider providerFor(_ListSource source) =>
    ResourceListProvider(source: source, resource: _resource);

void main() {
  test('load() fills records and applies the default sort', () async {
    final source = _ListSource();
    final provider = providerFor(source);

    await provider.load();

    expect(provider.status, LoadStatus.success);
    expect(provider.records, hasLength(2));
    expect(source.calls.single.page, 1);
    expect(source.calls.single.sort, 'created_at');
    expect(source.calls.single.direction, 'desc');
  });

  test('loadMore() appends the next page and stops at the last', () async {
    final provider = providerFor(_ListSource());

    await provider.load();
    expect(provider.hasMore, isTrue);

    await provider.loadMore();

    expect(provider.records, hasLength(4));
    expect(provider.records.map((r) => r.id), [10, 11, 20, 21]);
    expect(provider.hasMore, isFalse);
  });

  test('loadMore() is a no-op once there is no more', () async {
    final source = _ListSource();
    final provider = providerFor(source);

    await provider.load();
    await provider.loadMore();
    await provider.loadMore();

    expect(source.calls, hasLength(2));
  });

  test('search() resets to page one and replaces records', () async {
    final source = _ListSource();
    final provider = providerFor(source);

    await provider.load();
    await provider.loadMore();
    await provider.search('الأول');

    expect(provider.searchTerm, 'الأول');
    expect(source.calls.last.page, 1);
    expect(source.calls.last.search, 'الأول');
    expect(provider.records, hasLength(2));
  });

  test('sortBy() resets to page one and sends the new key', () async {
    final source = _ListSource();
    final provider = providerFor(source);

    await provider.load();
    await provider.sortBy(_resource.sorts.last);

    expect(provider.activeSort!.key, 'name');
    expect(source.calls.last.sort, 'name');
    expect(source.calls.last.direction, 'asc');
    expect(source.calls.last.page, 1);
  });

  test(
    'a failure sets failure with a message and keeps records empty',
    () async {
      final provider = providerFor(_ListSource(error: Exception('تعذّر')));

      await provider.load();

      expect(provider.status, LoadStatus.failure);
      expect(provider.errorMessage, contains('تعذّر'));
      expect(provider.records, isEmpty);
    },
  );

  test('a failure during loadMore keeps the records already shown, and sets '
      'errorMessage without leaving isLoadingMore stuck', () async {
    final source = _ListSource(failOnPage: 2);
    final provider = providerFor(source);

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
    // The session expiring mid-scroll. Keeping the rows and offering a retry
    // is right for a timeout and wrong here: every retry 401s the same way,
    // so the user sat on a generic error forever instead of being told they
    // were signed out. Both providers had the same hole.
    final provider = providerFor(
      _ListSource(
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
    final provider = providerFor(_ListSource(failOnPage: 2));

    await provider.load();
    await provider.loadMore();
    expect(provider.loadMoreFailed, isTrue);

    await provider.refresh();

    expect(provider.loadMoreFailed, isFalse);
  });

  // Sibling to the test above: the same rule is only meaningful as a pair —
  // a first-page failure empties records, a loadMore failure does not.
  // Covered by 'a failure sets failure with a message and keeps records
  // empty' further up.

  test('two providers do not share mutable state — one failing does not '
      'affect another that already loaded', () async {
    final source = _ListSource();
    final provider = providerFor(source);
    await provider.load();

    final failing = providerFor(_ListSource(error: Exception('boom')));
    await failing.load();

    expect(provider.records, hasLength(2));
    expect(failing.records, isEmpty);
  });

  test(
    'surfaces a FilamentTransportException message with no type prefix',
    () async {
      final provider = providerFor(
        _ListSource(error: const FilamentTransportException('تعذّر الاتصال')),
      );

      await provider.load();

      expect(provider.errorMessage, 'تعذّر الاتصال');
    },
  );

  test('refresh() reloads from page one', () async {
    final source = _ListSource();
    final provider = providerFor(source);

    await provider.load();
    await provider.loadMore();
    await provider.refresh();

    expect(source.calls.last.page, 1);
    expect(provider.records, hasLength(2));
  });
}
