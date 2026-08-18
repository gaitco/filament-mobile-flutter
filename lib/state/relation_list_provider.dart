import 'package:flutter/foundation.dart';

import '../data/resource_data_source.dart';
import '../data/resource_record.dart';
import '../data/write_result.dart';
import '../ports/filament_transport.dart';
import '../schema/relation_descriptor.dart';
import '../schema/resource_schema.dart' show ResourceSort;
import 'load_status.dart';

/// Owns one relation's full, paginated child rows — the screen `RelationSectionWidget`'s
/// "See all" opens.
///
/// A sibling to `ResourceListProvider`, not a subclass: it fetches through
/// `ResourceDataSource.relation()` — the same data source, never a closure a
/// host has to hand-wire, per that method's own docblock — and reads its
/// search/sort capabilities from the [RelationDescriptor] (P11), which since
/// P11 carries the same `search`/`sorts` blocks a resource schema does. The
/// search/sort behaviour mirrors `ResourceListProvider.search()`/`sortBy()`
/// exactly, including the reset to page one.
class RelationListProvider extends ChangeNotifier {
  RelationListProvider({
    required this._source,
    required this.resourceKey,
    required this.id,
    required this.relation,
  }) : _activeSort = relation.defaultSort;

  final ResourceDataSource _source;
  final String resourceKey;
  final Object id;
  final RelationDescriptor relation;

  LoadStatus _status = LoadStatus.initial;
  List<ResourceRecord> _records = const [];
  String? _errorMessage;
  bool _isUnauthenticated = false;
  bool _hasMore = false;
  bool _isLoadingMore = false;

  /// True right after the most recent `loadMore()` call failed — see that
  /// method's doc. Reset by every fresh fetch, never left stuck.
  bool _loadMoreFailed = false;
  int _page = 1;
  String _searchTerm = '';
  ResourceSort? _activeSort;

  /// Bumped by every fetch — same drop-stale-response guard as
  /// `ResourceListProvider._requestId`.
  int _requestId = 0;

  LoadStatus get status => _status;
  List<ResourceRecord> get records => _records;
  String? get errorMessage => _errorMessage;

  /// True when the load failed on a 401 — see [FilamentTransportException.statusCode].
  bool get isUnauthenticated => _isUnauthenticated;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get loadMoreFailed => _loadMoreFailed;
  String get searchTerm => _searchTerm;
  ResourceSort? get activeSort => _activeSort;

  Future<void> load() => _fetchFirstPage();

  Future<void> refresh() => _fetchFirstPage();

  /// Mirrors `ResourceListProvider.search()`: stores the term and refetches
  /// from page one. Debouncing lives in the screen, not here — the same
  /// division that type documents.
  Future<void> search(String term) {
    _searchTerm = term;
    return _fetchFirstPage();
  }

  /// Mirrors `ResourceListProvider.sortBy()`: the new key replaces the
  /// default (or the previous pick) and the list refetches from page one.
  Future<void> sortBy(ResourceSort sort) {
    _activeSort = sort;
    return _fetchFirstPage();
  }

  /// The data source this provider fetches through, exposed so the relation
  /// list screen can build a row's `ResourceFormProvider` against the SAME
  /// connection — never a second one a host would have to hand-wire.
  ResourceDataSource get source => _source;

  /// The relation-row writes (P9). Each goes through the relationship on the
  /// server (a child that is not this parent's is a 404, never a cross-parent
  /// write), returns the server's verdict as data — a 422 keyed by the CHILD
  /// resource's field names included, for the caller's form to render — and
  /// on success reloads through the list's own [refresh]: the write changed
  /// this page's membership, and re-fetching page one is the refresh the
  /// class already owns rather than a client-side row edit the server never
  /// confirmed.
  Future<WriteResult> create(Map<String, dynamic> values) async {
    final result = await _source.createRelation(
      resourceKey,
      id,
      relation,
      values,
    );
    if (result is WriteSuccess) await refresh();
    return result;
  }

  /// [childId] is the child's own key value — the relation's `recordKey`,
  /// routinely not `id`; see `ResourceDataSource.updateRelation`.
  Future<WriteResult> update(
    Object childId,
    Map<String, dynamic> values,
  ) async {
    final result = await _source.updateRelation(
      resourceKey,
      id,
      relation,
      childId,
      values,
    );
    if (result is WriteSuccess) await refresh();
    return result;
  }

  /// A [WriteGone] refreshes too: the row is gone either way — the same
  /// outcome as deleting it ourselves, and `ResourceViewScreen`'s record
  /// delete already treats the two as one.
  Future<WriteResult> delete(Object childId) async {
    final result = await _source.deleteRelation(
      resourceKey,
      id,
      relation,
      childId,
    );
    if (result is WriteSuccess || result is WriteGone) await refresh();
    return result;
  }

  Future<void> _fetchFirstPage() async {
    final requestId = ++_requestId;

    _status = LoadStatus.loading;
    _errorMessage = null;
    _isUnauthenticated = false;
    _isLoadingMore = false;
    _loadMoreFailed = false;
    _records = const [];
    notifyListeners();

    try {
      final page = await _source.relation(
        resourceKey,
        id,
        relation,
        page: 1,
        search: _searchTerm,
        sort: _activeSort?.key,
        direction: _activeSort?.direction,
      );

      if (requestId != _requestId) return;

      _records = page.records;
      _page = page.meta.currentPage;
      _hasMore = page.meta.hasMore;
      _status = LoadStatus.success;
    } catch (e) {
      if (requestId != _requestId) return;

      // A 403 falls through to the generic branch below and still lands on
      // `LoadStatus.failure` — never `success` with zero records — so the
      // screen shows the server's own permission message, not an empty
      // list wearing a different, false statement. See the module doc.
      if (e is FilamentTransportException && e.statusCode == 401) {
        _isUnauthenticated = true;
      }
      _errorMessage = messageOf(e);
      _status = LoadStatus.failure;
    }

    notifyListeners();
  }

  /// Appends the next page — same trade as `ResourceListProvider.loadMore()`:
  /// a failure here keeps whatever is already on screen, but [loadMoreFailed]
  /// still flips so the trailing row can show a retry instead of a spinner
  /// that never resolves into anything the user is told about. A 401 is that
  /// method's same exception, for its same reason.
  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore || _status.isLoading) return;

    final requestId = ++_requestId;

    _isLoadingMore = true;
    _loadMoreFailed = false;
    _errorMessage = null;
    notifyListeners();

    try {
      final page = await _source.relation(
        resourceKey,
        id,
        relation,
        page: _page + 1,
        search: _searchTerm,
        sort: _activeSort?.key,
        direction: _activeSort?.direction,
      );

      if (requestId != _requestId) return;

      _records = [..._records, ...page.records];
      _page = page.meta.currentPage;
      _hasMore = page.meta.hasMore;
    } catch (e) {
      if (requestId != _requestId) return;

      _errorMessage = messageOf(e);
      _loadMoreFailed = true;

      if (e is FilamentTransportException && e.statusCode == 401) {
        _isUnauthenticated = true;
        _status = LoadStatus.failure;
      }
    }

    _isLoadingMore = false;
    notifyListeners();
  }
}
