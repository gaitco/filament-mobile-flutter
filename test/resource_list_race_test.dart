import 'dart:async';

import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:filament_mobile/state/resource_list_provider.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hands back a [Completer] per call so a test can land responses out of the
/// order they were requested — the whole point of the sequencing guard.
class _GatedSource implements ResourceDataSource {
  @override
  Future<void> reorder(String resourceKey, List<Object> ids) =>
      throw UnimplementedError();
  final List<Completer<PaginatedRecords>> pending = [];
  final List<({int page, String? search})> calls = [];

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
  }) {
    calls.add((page: page, search: search));
    final completer = Completer<PaginatedRecords>();
    pending.add(completer);
    return completer.future;
  }

  void land(int call, List<int> ids, {int page = 1, int lastPage = 1}) {
    pending[call].complete(
      PaginatedRecords(
        records: [for (final id in ids) ResourceRecord(id: id)],
        meta: PageMeta(
          currentPage: page,
          lastPage: lastPage,
          perPage: 2,
          total: 99,
        ),
      ),
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
}, 'r');

/// Two races the 400 ms search debounce narrows but does not close. Both are
/// reachable by ordinary use, and both are silent: the list shows one query's
/// rows under another query's term.
void main() {
  // The screen's 400 ms debounce narrows this window; it does not close it.
  // A slow first query landing after a fast second one leaves the newer
  // term on screen above the older query's rows.
  test('a stale search response never overwrites a newer one', () async {
    final source = _GatedSource();
    final provider = ResourceListProvider(source: source, resource: _resource);

    final stale = provider.search('قديم');
    final fresh = provider.search('جديد');

    source.land(1, [2], lastPage: 1); // the newer query lands first
    source.land(0, [1], lastPage: 5); // then the older one
    await Future.wait([stale, fresh]);

    expect(provider.searchTerm, 'جديد');
    expect(provider.records.map((r) => r.id), [2]);
    expect(
      provider.hasMore,
      isFalse,
      reason:
          'hasMore came from the stale '
          'page — the user would scroll into the wrong query',
    );
    expect(provider.status, LoadStatus.success);
  });

  // Reachable by ordinary use: the scroll listener fires loadMore() at 80%,
  // then the user types. The search replaces the result set and the stale
  // page two is appended to it.
  test('a page in flight when the user searches is not appended', () async {
    final source = _GatedSource();
    final provider = ResourceListProvider(source: source, resource: _resource);

    final first = provider.load();
    source.land(0, [10, 11], lastPage: 2);
    await first;
    expect(provider.hasMore, isTrue);

    final more = provider.loadMore(); // page two in flight
    final searching = provider.search('جديد');

    source.land(2, [99], lastPage: 1); // the search lands
    source.land(1, [20, 21], page: 2, lastPage: 2); // then the stale page
    await Future.wait([more, searching]);

    expect(provider.records.map((r) => r.id), [99]);
    expect(provider.hasMore, isFalse);
    expect(provider.isLoadingMore, isFalse);
    expect(source.calls.last.search, 'جديد');
  });
}
