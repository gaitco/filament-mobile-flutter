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
  @override
  Future<void> reorder(String resourceKey, List<Object> ids) =>
      throw UnimplementedError();
  _ListSource({this.error, this.failOnPage});

  Object? error;

  /// When set, `list()` throws only once `page` reaches this value —
  /// lets a test succeed on page one and fail on page two.
  final int? failOnPage;
  final List<
    ({
      int page,
      String? search,
      String? sort,
      String? direction,
      bool reorder,
      Map<String, Object?> filters,
    })
  >
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
    bool reorder = false,
    Map<String, Object?> filters = const {},
  }) async {
    calls.add((
      page: page,
      search: search,
      sort: sort,
      direction: direction,
      reorder: reorder,
      filters: filters,
    ));
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

/// Carries two filter nodes (P24) — the same `select`-shaped node the server
/// publishes for both a `SelectFilter` and a `MultiSelectFilter` (see
/// `PublishedFilter::toNode()`): one with a scalar `default`, one with a
/// `multiple` array `default` — so seeding exercises both branches.
ResourceSchema get _resourceWithFilters => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'لافتة', 'plural': 'اللافتات'},
  'search': {'enabled': true},
  'filters': [
    {
      'type': 'select',
      'name': 'status',
      'label': 'Status',
      'config': {
        'options': [
          {'value': 'draft', 'label': 'Draft'},
          {'value': 'published', 'label': 'Published'},
        ],
      },
      'default': 'draft',
    },
    {
      'type': 'select',
      'name': 'tags',
      'label': 'Tags',
      'config': {
        'options': [
          {'value': 'a', 'label': 'A'},
          {'value': 'b', 'label': 'B'},
        ],
        'multiple': true,
      },
      'default': ['a', 'b'],
    },
  ],
}, 'r');

/// One `->multiple()->default([])` filter — publishable, and "no default at
/// all" on both sides of the wire.
ResourceSchema get _resourceWithEmptyListDefault =>
    ResourceSchema.fromJson(const {
      'key': 'banners',
      'labels': {'singular': 'لافتة', 'plural': 'اللافتات'},
      'filters': [
        {
          'type': 'select',
          'name': 'tags',
          'label': 'Tags',
          'config': {
            'options': [
              {'value': 'a', 'label': 'A'},
            ],
            'multiple': true,
          },
          'default': <String>[],
        },
      ],
    }, 'r');

ResourceListProvider _providerFor(_ListSource source) =>
    ResourceListProvider(source: source, resource: _resource);

ResourceListProvider _providerForResource(
  _ListSource source,
  ResourceSchema resource,
) => ResourceListProvider(source: source, resource: resource);

void main() {
  test('load() fills records and applies the default sort', () async {
    final source = _ListSource();
    final provider = _providerFor(source);

    await provider.load();

    expect(provider.status, LoadStatus.success);
    expect(provider.records, hasLength(2));
    expect(source.calls.single.page, 1);
    expect(source.calls.single.sort, 'created_at');
    expect(source.calls.single.direction, 'desc');
  });

  test('loadMore() appends the next page and stops at the last', () async {
    final provider = _providerFor(_ListSource());

    await provider.load();
    expect(provider.hasMore, isTrue);

    await provider.loadMore();

    expect(provider.records, hasLength(4));
    expect(provider.records.map((r) => r.id), [10, 11, 20, 21]);
    expect(provider.hasMore, isFalse);
  });

  test('loadMore() is a no-op once there is no more', () async {
    final source = _ListSource();
    final provider = _providerFor(source);

    await provider.load();
    await provider.loadMore();
    await provider.loadMore();

    expect(source.calls, hasLength(2));
  });

  test('search() resets to page one and replaces records', () async {
    final source = _ListSource();
    final provider = _providerFor(source);

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
    final provider = _providerFor(source);

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
      final provider = _providerFor(_ListSource(error: Exception('تعذّر')));

      await provider.load();

      expect(provider.status, LoadStatus.failure);
      expect(provider.errorMessage, contains('تعذّر'));
      expect(provider.records, isEmpty);
    },
  );

  test('a failure during loadMore keeps the records already shown, and sets '
      'errorMessage without leaving isLoadingMore stuck', () async {
    final source = _ListSource(failOnPage: 2);
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
    // The session expiring mid-scroll. Keeping the rows and offering a retry
    // is right for a timeout and wrong here: every retry 401s the same way,
    // so the user sat on a generic error forever instead of being told they
    // were signed out. Both providers had the same hole.
    final provider = _providerFor(
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
    final provider = _providerFor(_ListSource(failOnPage: 2));

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
    final provider = _providerFor(source);
    await provider.load();

    final failing = _providerFor(_ListSource(error: Exception('boom')));
    await failing.load();

    expect(provider.records, hasLength(2));
    expect(failing.records, isEmpty);
  });

  test(
    'surfaces a FilamentTransportException message with no type prefix',
    () async {
      final provider = _providerFor(
        _ListSource(error: const FilamentTransportException('تعذّر الاتصال')),
      );

      await provider.load();

      expect(provider.errorMessage, 'تعذّر الاتصال');
    },
  );

  test('refresh() reloads from page one', () async {
    final source = _ListSource();
    final provider = _providerFor(source);

    await provider.load();
    await provider.loadMore();
    await provider.refresh();

    expect(source.calls.last.page, 1);
    expect(provider.records, hasLength(2));
  });

  test('a background refresh keeps good rows on a transient failure', () async {
    final source = _ListSource();
    final provider = _providerFor(source);

    await provider.load();
    source.error = const FilamentTransportException('offline');
    await provider.refresh(keepPrevious: true);

    expect(provider.status, LoadStatus.success);
    expect(provider.records, hasLength(2));
    expect(provider.errorMessage, 'offline');
  });

  group('filters (P24)', () {
    // Belt and braces, not the only line of defence — the server applies
    // each filter node's `default` too (P24 Task 2), so a stale/older
    // client still sees a filtered list even without this. Do not delete
    // this seeding just because the server also does it.
    test(
      "filter node defaults seed provider.filters and are sent on load()",
      () async {
        final source = _ListSource();
        final provider = _providerForResource(source, _resourceWithFilters);

        expect(provider.filters, {
          'status': 'draft',
          'tags': ['a', 'b'],
        });
        expect(provider.activeFilterCount, 2);

        await provider.load();

        expect(source.calls.single.filters, {
          'status': 'draft',
          'tags': ['a', 'b'],
        });
      },
    );

    // Final wave, finding 4: seeding is a SECOND write point into
    // `_filters`, and it used to bypass the canonicalisation `setFilter`
    // applies at the first one. A publishable `->multiple()->default([])`
    // therefore seeded an empty `List` verbatim — a badge reading 1 and a
    // blank `InputChip` with a delete icon, for a wire value (`filter[x]=`)
    // that is no filter at all.
    test('an empty list default seeds nothing — no phantom active filter', () {
      final provider = _providerForResource(
        _ListSource(),
        _resourceWithEmptyListDefault,
      );

      expect(provider.filters, isEmpty);
      expect(provider.activeFilterCount, 0);
    });

    test("setFilter() refetches page one with the filter and bumps "
        'activeFilterCount', () async {
      final source = _ListSource();
      final provider = _providerFor(source); // no filter nodes/defaults

      await provider.load();
      await provider.setFilter('status', 'draft');

      expect(provider.filters, {'status': 'draft'});
      expect(provider.activeFilterCount, 1);
      expect(source.calls.last.page, 1);
      expect(source.calls.last.filters, {'status': 'draft'});
    });

    // Review fix round 1: clearing is EXPLICIT, never implicit. The server
    // (mobile-core ListQuery::filters()) treats an OMITTED filter key as
    // "apply this filter's default" and only an explicit empty value
    // (`filter[status]=`) as "any" — so removing the key entirely, as an
    // earlier version of this method did, would make a defaulted filter
    // unclearable: the very next request would reinstate the default.
    test('setFilter(name, null) clears that filter EXPLICITLY (an empty '
        'string, never a removed key) so a defaulted filter cannot be '
        'silently reinstated by the server', () async {
      final source = _ListSource();
      final provider = _providerFor(source);
      await provider.setFilter('status', 'draft');

      await provider.setFilter('status', null);

      expect(provider.filters, {'status': ''});
      expect(
        provider.activeFilterCount,
        0,
        reason:
            'an explicitly-cleared filter is inactive, even though '
            'its key stays in the map',
      );
      expect(source.calls.last.filters, {'status': ''});
    });

    // Review fix round 1, finding 1: `SelectFieldWidget._multi` reports an
    // empty `List` (every checkbox unchecked), never `null` — a multiselect
    // filter can't reach setFilter's `null` branch at all. Without this
    // canonicalisation `[]` would sit in `_filters` as a THIRD "cleared"
    // shape alongside `null`'s `''`, which `_filterChipsRow`'s `!= ''`
    // guard and `activeFilterCount`'s identical check both miss — a blank
    // chip with a working delete icon, and a badge counting a filter
    // nobody has selected anything for.
    test('setFilter(name, []) — every checkbox of a multiselect filter '
        'deselected — clears that filter the SAME way null does, not as a '
        'third representation', () async {
      final source = _ListSource();
      final provider = _providerFor(source);
      await provider.setFilter('tags', ['a', 'b']);

      await provider.setFilter('tags', <String>[]);

      expect(provider.filters, {'tags': ''});
      expect(provider.activeFilterCount, 0);
      // The wire output is unchanged either way (`ResourceDataSource.list`'s
      // query builder already emits the bare `filter[tags]=` for an empty
      // `List` too) — this assertion is about `_filters`' own shape, not a
      // behaviour change on the wire.
      expect(source.calls.last.filters, {'tags': ''});
    });

    test(
      'clearFilters() sets EVERY filter the schema publishes — including '
      'ones never touched — to the explicit empty value, and refetches',
      () async {
        final source = _ListSource();
        final provider = _providerForResource(source, _resourceWithFilters);
        await provider.load(); // sends the seeded defaults

        await provider.clearFilters();

        expect(provider.filters, {'status': '', 'tags': ''});
        expect(provider.activeFilterCount, 0);
        expect(source.calls.last.filters, {'status': '', 'tags': ''});
        expect(source.calls.last.page, 1);
      },
    );

    test('a resource with no filter nodes seeds no filters and sends no '
        'filter key at all', () async {
      final source = _ListSource();
      final provider = _providerFor(source); // _resource has no filters

      await provider.load();

      expect(provider.filters, isEmpty);
      expect(provider.activeFilterCount, 0);
      expect(source.calls.single.filters, isEmpty);
    });

    test('a filter set while reordering refetches the reordered page with the '
        'filter, not the paginated list', () async {
      final source = _ListSource();
      final provider = _providerFor(source);
      await provider.enterReorderMode();

      await provider.setFilter('status', 'draft');

      expect(provider.isReordering, isTrue);
      expect(source.calls.last.reorder, isTrue);
      expect(source.calls.last.filters, {'status': 'draft'});
    });

    test('loadMore() carries the active filters, not just page and search — '
        'otherwise page two silently widens the list mid-scroll', () async {
      final source = _ListSource();
      final provider = _providerFor(source);
      await provider.setFilter('status', 'draft');
      expect(provider.hasMore, isTrue);

      await provider.loadMore();

      expect(source.calls.last.page, 2);
      expect(source.calls.last.filters, {'status': 'draft'});
    });
  });
}
