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
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:filament_mobile/state/relation_list_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _relation = RelationDescriptor(
  key: 'tags',
  label: 'Tags',
  card: CardLayout(titleField: 'name'),
);

/// The P11 shape: a relation whose server declared search and sorts — the
/// same fixture `panel.json`'s `roles` node and `laravel-panel.json`'s `tags`
/// node publish.
const _searchableRelation = RelationDescriptor(
  key: 'tags',
  label: 'Tags',
  card: CardLayout(titleField: 'name'),
  search: ResourceSearch(enabled: true),
  sorts: [
    ResourceSort(key: 'name', label: 'Name', isDefault: true),
    ResourceSort(key: 'created_at', label: 'Created', direction: 'desc'),
  ],
);

/// Sibling to `resource_list_provider_test.dart`'s `_ListSource`: `relation()`
/// serves two DISTINCT, real pages so `loadMore()` genuinely appends rather
/// than repeating page one, and records the page argument each call actually
/// carried.
class _RelationSource implements ResourceDataSource {
  @override
  Future<void> reorder(String resourceKey, List<Object> ids) =>
      throw UnimplementedError();
  _RelationSource({
    this.error,
    this.failOnPage,
    this.writeResult = const WriteSuccess({}),
  });

  final Object? error;

  /// When set, `relation()` throws only once `page` reaches this value —
  /// lets a test succeed on page one and fail on page two.
  final int? failOnPage;

  final List<int> pages = [];

  /// The search/sort params the most recent `relation()` call carried (P11) —
  /// the provider-facing half of the REST data source's query-string tests.
  String? lastSearch;
  String? lastSort;
  String? lastDirection;

  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async {
    pages.add(page);
    lastSearch = search;
    lastSort = sort;
    lastDirection = direction;
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

  /// The relation writes record which one fired and with whose coordinates,
  /// so a test can assert the provider aimed at the right endpoint; the
  /// result each returns is settable per test ([writeResult]).
  final List<String> writes = [];
  Object? lastChildId;
  Map<String, dynamic>? lastValues;
  WriteResult writeResult;

  @override
  Future<WriteResult> createRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Map<String, dynamic> values,
  ) async {
    writes.add('create');
    lastValues = values;
    return writeResult;
  }

  @override
  Future<WriteResult> updateRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
    Map<String, dynamic> values,
  ) async {
    writes.add('update');
    lastChildId = childId;
    lastValues = values;
    return writeResult;
  }

  @override
  Future<WriteResult> deleteRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
  ) async {
    writes.add('delete');
    lastChildId = childId;
    return writeResult;
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
    bool reorder = false,
    Map<String, Object?> filters = const {},
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

RelationListProvider _providerFor(
  _RelationSource source, {
  RelationDescriptor relation = _relation,
}) => RelationListProvider(
  source: source,
  resourceKey: 'banners',
  id: 7,
  relation: relation,
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

  group('search/sort (P11)', () {
    test('load() applies the declared default sort, mirroring '
        'ResourceListProvider', () async {
      final source = _RelationSource();
      final provider = _providerFor(source, relation: _searchableRelation);

      await provider.load();

      expect(provider.activeSort!.key, 'name');
      expect(source.lastSort, 'name');
      expect(source.lastDirection, 'asc');
    });

    test('a relation with no declared sorts sends none', () async {
      // The pre-P11 shape: absent sorts means no sort parameter, so the
      // server's own defaulting — never a client-invented key — decides.
      final source = _RelationSource();
      final provider = _providerFor(source);

      await provider.load();

      expect(provider.activeSort, isNull);
      expect(source.lastSort, isNull);
      expect(source.lastDirection, isNull);
    });

    test('search() resets to page one and sends the term', () async {
      final source = _RelationSource();
      final provider = _providerFor(source, relation: _searchableRelation);

      await provider.load();
      await provider.loadMore();
      await provider.search('sale');

      expect(provider.searchTerm, 'sale');
      expect(source.pages.last, 1);
      expect(source.lastSearch, 'sale');
      expect(provider.records.map((r) => r.id), [10, 11]);
    });

    test(
      'sortBy() resets to page one and sends the new key and direction',
      () async {
        final source = _RelationSource();
        final provider = _providerFor(source, relation: _searchableRelation);

        await provider.load();
        await provider.sortBy(_searchableRelation.sorts.last);

        expect(provider.activeSort!.key, 'created_at');
        expect(source.lastSort, 'created_at');
        expect(source.lastDirection, 'desc');
        expect(source.pages.last, 1);
      },
    );
  });

  group('row writes (P9)', () {
    test('create() posts through the relation endpoint and refreshes the '
        'loaded page on success', () async {
      final source = _RelationSource();
      final provider = _providerFor(source);
      await provider.load();
      expect(source.pages, [1]);

      final result = await provider.create({'name': 'sale'});

      expect(result, isA<WriteSuccess>());
      expect(source.writes, ['create']);
      expect(source.lastValues, {'name': 'sale'});
      // The write changed this page's membership; the provider re-fetches
      // page one through its own refresh rather than editing rows the server
      // never confirmed.
      expect(source.pages, [1, 1]);
      expect(provider.status, LoadStatus.success);
    });

    test('update() carries the child id — the relation\'s recordKey value, '
        'here a slug — and refreshes on success', () async {
      final source = _RelationSource();
      final provider = _providerFor(source);
      await provider.load();

      final result = await provider.update('sale', {'name': 'clearance'});

      expect(result, isA<WriteSuccess>());
      expect(source.writes, ['update']);
      expect(source.lastChildId, 'sale');
      expect(source.pages, [1, 1]);
    });

    test(
      'delete() refreshes on WriteGone too — the row is gone either way',
      () async {
        final source = _RelationSource(
          writeResult: const WriteGone('No record.'),
        );
        final provider = _providerFor(source);
        await provider.load();

        final result = await provider.delete('sale');

        expect(result, isA<WriteGone>());
        expect(source.pages, [1, 1]);
      },
    );

    test('a 422 comes back as WriteInvalid keyed by field and does NOT '
        'refresh — nothing changed server-side', () async {
      final source = _RelationSource(
        writeResult: const WriteInvalid({
          'name': ['The name field is required.'],
        }),
      );
      final provider = _providerFor(source);
      await provider.load();

      final result = await provider.create(const {});

      expect(result, isA<WriteInvalid>());
      expect((result as WriteInvalid).errors['name'], [
        'The name field is required.',
      ]);
      expect(source.pages, [1], reason: 'no write landed, so no re-fetch');
    });

    test('a denial comes back as WriteDenied and does NOT refresh', () async {
      final source = _RelationSource(
        writeResult: const WriteDenied('This action is unauthorized.'),
      );
      final provider = _providerFor(source);
      await provider.load();

      final result = await provider.delete('sale');

      expect(result, isA<WriteDenied>());
      expect(source.pages, [1]);
    });
  });
}
