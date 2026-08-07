import 'package:flutter/foundation.dart';

import '../data/resource_data_source.dart';
import '../data/resource_record.dart';
import '../ports/filament_transport.dart';
import '../schema/relation_descriptor.dart';
import 'load_status.dart';

/// Owns one relation's full, paginated child rows — the screen `RelationSectionWidget`'s
/// "See all" opens.
///
/// Deliberately not `ResourceListProvider`: that type is hard-wired to
/// `ResourceDataSource.list()` and its search/sort parameters, neither of
/// which a relation has (`RelationDescriptor` carries no `search`/`sorts`
/// block). Fetching goes through `ResourceDataSource.relation()` instead —
/// the same data source, never a closure a host has to hand-wire, per that
/// method's own docblock.
class RelationListProvider extends ChangeNotifier {
  RelationListProvider({
    required this._source,
    required this.resourceKey,
    required this.id,
    required this.relation,
  });

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

  Future<void> load() => _fetchFirstPage();

  Future<void> refresh() => _fetchFirstPage();

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
      final page = await _source.relation(resourceKey, id, relation, page: 1);

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
