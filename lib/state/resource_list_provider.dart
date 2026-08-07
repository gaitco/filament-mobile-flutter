import 'package:flutter/foundation.dart';

import '../data/resource_data_source.dart';
import '../data/resource_record.dart';
import '../ports/filament_transport.dart';
import '../schema/resource_schema.dart';
import 'load_status.dart';

/// Owns one resource's list: records, search term, active sort, pagination.
///
/// Debouncing lives in the screen, not here — a provider owning a timer is
/// untestable without pumping fake async, and the screen is where the keystroke
/// actually arrives.
class ResourceListProvider extends ChangeNotifier {
  ResourceListProvider({
    required ResourceDataSource source,
    required this.resource,
  }) : _source = source,
       _activeSort = resource.defaultSort;

  final ResourceDataSource _source;
  final ResourceSchema resource;

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

  /// Bumped by every fetch. A response whose id no longer matches lost the
  /// race — the user searched again, or searched while a page was in flight —
  /// and is dropped rather than merged, which would otherwise show one query's
  /// rows under another query's term.
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

  Future<void> search(String term) {
    _searchTerm = term;
    return _fetchFirstPage();
  }

  Future<void> sortBy(ResourceSort sort) {
    _activeSort = sort;
    return _fetchFirstPage();
  }

  Future<void> _fetchFirstPage() async {
    final requestId = ++_requestId;

    _status = LoadStatus.loading;
    _errorMessage = null;
    _isUnauthenticated = false;
    // A page-two fetch may still be in flight; it will drop its own result,
    // and clearing the flag here is what releases loadMore() again.
    _isLoadingMore = false;
    _loadMoreFailed = false;
    // Skeleton geometry: the screen renders fake cards while loading, so the
    // real records must not linger underneath and then jump.
    _records = const [];
    notifyListeners();

    try {
      final page = await _source.list(
        resource.key,
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

      if (e is FilamentTransportException && e.statusCode == 401) {
        _isUnauthenticated = true;
      }
      _errorMessage = messageOf(e);
      _status = LoadStatus.failure;
    }

    notifyListeners();
  }

  /// Appends the next page. A failure here keeps whatever is already on
  /// screen — losing a scrolled list because page four timed out is worse
  /// than the missing page — but [loadMoreFailed] still flips, so the
  /// trailing row can show a retry instead of a spinner that never resolves
  /// into anything the user is told about.
  ///
  /// A 401 is the exception, and it is why [isUnauthenticated] is set here
  /// too: the session is gone, so every retry the trailing row offers will
  /// fail the same way, and the screen has to be told to route to the
  /// unauthenticated state rather than show a generic retry forever. Keeping
  /// the rows is right for a timeout and wrong for a signed-out user.
  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore || _status.isLoading) return;

    final requestId = ++_requestId;

    _isLoadingMore = true;
    _loadMoreFailed = false;
    _errorMessage = null;
    notifyListeners();

    try {
      final page = await _source.list(
        resource.key,
        page: _page + 1,
        search: _searchTerm,
        sort: _activeSort?.key,
        direction: _activeSort?.direction,
      );

      // Appending a stale page would splice the previous query's rows into the
      // new result set, and take `hasMore` from the wrong query.
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
