import 'package:flutter/foundation.dart';

import '../data/resource_data_source.dart';
import '../data/options_page.dart';
import '../data/resource_record.dart';
import '../ports/filament_transport.dart';
import '../schema/resource_schema.dart';
import '../schema/schema_component.dart';
import 'load_status.dart';

/// Owns one resource's list: records, search term, active sort, pagination.
///
/// Debouncing lives in the screen, not here — a provider owning a timer is
/// untestable without pumping fake async, and the screen is where the keystroke
/// actually arrives.
class ResourceListProvider extends ChangeNotifier {
  ResourceListProvider({required this.source, required this.resource})
    : _activeSort = resource.defaultSort,
      _filters = _seedFilters(resource);

  final ResourceDataSource source;
  final ResourceSchema resource;

  /// Seeds filter state from each filter node's declared `default` (P24) —
  /// so a freshly opened list shows the same default view the web panel
  /// does. This is belt-and-braces, NOT the only line of defence: the
  /// server applies each filter node's default too (Task 2), so a stale or
  /// older client still sees a filtered list even without this. Do not
  /// delete this seeding on the strength of the server also doing it, or
  /// vice versa — both exist on purpose.
  ///
  /// Filter nodes are always published as a `select`-shaped
  /// [SelectComponent] (`PublishedFilter::toNode()`), never any other
  /// component type — the `is! SelectComponent` guard is defensive, not
  /// reachable today.
  static Map<String, Object?> _seedFilters(ResourceSchema resource) {
    final seeded = <String, Object?>{};
    for (final node in resource.filters) {
      if (node is! SelectComponent) continue;
      final name = node.name;
      final defaultValue = node.defaultValue;
      if (name == null || defaultValue == null) continue;

      final seedable = defaultValue is List
          ? [for (final value in defaultValue) '$value']
          : defaultValue;

      // Seeding is the SECOND write point into [_filters], so it owes the
      // same canonicalisation [setFilter] applies at the first: an empty
      // `List` is no filter, not a filter whose value is empty. Left
      // verbatim, a publishable `->multiple()->default([])` produced a badge
      // reading 1 and a blank `InputChip` with a delete icon, for a wire
      // value (`filter[x]=`) that filters nothing. Absent, not `''` — the
      // node has no default to override, so there is nothing to clear.
      if (seedable is List && seedable.isEmpty) continue;

      seeded[name] = seedable;
    }
    return seeded;
  }

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

  /// name => `String` (single value) or `List<String>` (multiple) — see
  /// [_seedFilters] for how this starts, and [ResourceDataSource.list]'s
  /// doc for how a `List<String>` value is put on the wire.
  ///
  /// An empty string `''` is a distinct third state: EXPLICITLY cleared, as
  /// opposed to a key simply absent from this map. This matters because the
  /// server (Task 3, mobile-core `ListQuery::filters()`) treats an OMITTED
  /// filter as "apply this filter's declared default" and only an EXPLICIT
  /// empty value (`?filter[status]=`) as "any". If clearing a filter just
  /// removed its key, a filter that carries a `default` would be
  /// unclearable from the client — the server would silently reinstate the
  /// default on the very next request. See [setFilter]/[clearFilters].
  Map<String, Object?> _filters;

  /// True while the list is in drag-to-reorder mode (P18) — see
  /// [enterReorderMode]. The screen swaps its whole body for a
  /// `ReorderableListView` while this is true, rather than nesting one
  /// inside the other.
  bool _isReordering = false;
  List<ResourceRecord> _reorderedRecords = const [];

  /// The full, reorder-ordered list as last confirmed by the server —
  /// restored into [_reorderedRecords] when a drag is abandoned
  /// ([exitReorderMode]) or a [saveReorder] POST fails, so an in-flight drag
  /// that never committed leaves no trace.
  List<ResourceRecord> _serverReorderedRecords = const [];
  bool _isSavingReorder = false;

  /// Bumped by every fetch, and by [moveRecord]/[exitReorderMode]/
  /// [saveReorder] too. A response whose id no longer matches lost the race —
  /// the user searched again, searched while a page was in flight, dragged a
  /// row, cancelled, or saved — and is dropped rather than merged, which
  /// would otherwise show one query's rows under another query's term, or a
  /// reorder-mode fetch clobbering a drag/Cancel/Done that happened after it
  /// was sent.
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

  /// name => `String` | `List<String>` — a SNAPSHOT copy at the moment of
  /// the call, not a live view: both [setFilter] and [clearFilters]
  /// reassign the backing map rather than mutate it in place, so a
  /// previously-returned value never reflects a later change. Re-read this
  /// getter after [notifyListeners] fires (a listening widget already does,
  /// on every rebuild) rather than holding onto one call's result.
  Map<String, Object?> get filters => Map.unmodifiable(_filters);

  /// Counts every entry in [filters], INCLUDING a filter node's seeded
  /// `default` that the user has not touched — so a resource with two
  /// defaulted filters reports `2` from the very first frame, before any
  /// interaction. This is deliberate, not a side effect of [_seedFilters]:
  /// Filament's own web panel shows an indicator chip for a defaulted
  /// filter too, so this is parity with it, and a default the user cannot
  /// see applied is worse than a badge counting one they didn't set
  /// themselves. Task 5's filter-count badge should read this as-is rather
  /// than trying to subtract seeded defaults back out.
  ///
  /// Does NOT count an explicitly-cleared filter (value `''`, see
  /// [_filters]'s doc) — a cleared filter is inactive by definition, even
  /// though its key stays in the map.
  int get activeFilterCount => _filters.values.where((v) => v != '').length;

  /// True while a drag-to-reorder session (P18) is open — see
  /// [enterReorderMode].
  bool get isReordering => _isReordering;

  /// The full, unpaginated list in its current drag order. Only meaningful
  /// while [isReordering] — empty otherwise.
  List<ResourceRecord> get reorderedRecords => _reorderedRecords;

  /// True while [saveReorder]'s POST is in flight.
  bool get isSavingReorder => _isSavingReorder;

  Future<void> load() => _fetchFirstPage();

  /// Refetches page one. [keepPrevious] is used by background polling so an
  /// unchanged or transiently-failed refresh never flashes a skeleton over a
  /// list the user was already reading.
  Future<void> refresh({bool keepPrevious = false}) =>
      _fetchFirstPage(keepPrevious: keepPrevious);

  /// While [isReordering], this refetches the reorder-ordered list WITH the
  /// term (`?reorder=1&search=...`) instead of the hidden paginated list —
  /// Filament keeps its own search filter active while reordering, and a
  /// search box that visibly renders but only ever touches the paginated
  /// list underneath [reorderedRecords] would be exactly the silent no-op
  /// this screen's own class doc argues against.
  Future<void> search(String term) {
    _searchTerm = term;
    return _isReordering ? _fetchReorderedPage() : _fetchFirstPage();
  }

  Future<void> sortBy(ResourceSort sort) {
    _activeSort = sort;
    return _fetchFirstPage();
  }

  /// Sets or clears one filter (P24) and refetches page one — the
  /// reorder-ordered page instead, while [isReordering], same as [search].
  ///
  /// Clearing is explicit, never implicit: `value: null` does NOT remove
  /// `name` from [_filters] — it records `''`, the same "any" value the
  /// server itself recognises (`ListQuery::filters()`). Removing the key
  /// instead would mean OMITTING it, which the server reads as "apply this
  /// filter's default" — so a defaulted filter would silently reinstate
  /// itself the moment the client tried to clear it. See [_filters]'s doc.
  ///
  /// An empty `List` — every checkbox of a multiselect filter deselected —
  /// is canonicalised to `''` too, the SAME cleared value `null` produces,
  /// rather than stored as-is: `[]` and `''` both mean "no filter", and
  /// leaving `[]` as a second representation would give every reader of
  /// [_filters] (the chip row, [activeFilterCount], the wire encoder) a
  /// state to special-case instead of one to just check `!= ''` against.
  /// The wire output is unchanged either way — `ResourceDataSource.list`'s
  /// query builder already emits the bare `filter[name]=` for both an empty
  /// `List` and an empty `String`.
  Future<void> setFilter(String name, Object? value) {
    final cleared = value == null || (value is List && value.isEmpty);
    _filters = {..._filters, name: cleared ? '' : value};
    return _isReordering ? _fetchReorderedPage() : _fetchFirstPage();
  }

  /// Clears EVERY filter this resource's schema publishes — including ones
  /// never touched and ones with no seeded default — to the explicit `''`
  /// "any" value, and refetches: the reorder-ordered page instead while
  /// [isReordering]. Same reasoning as [setFilter]: writing `''` for every
  /// published filter name (rather than emptying the map) is what stops
  /// the server from reinstating any of their defaults on the next request.
  Future<void> clearFilters() {
    _filters = {
      for (final node in resource.filters)
        if (node is SelectComponent && node.name != null) node.name!: '',
    };
    return _isReordering ? _fetchReorderedPage() : _fetchFirstPage();
  }

  /// Searches one filter's remote options through an optional source
  /// capability. Existing custom [ResourceDataSource] implementations remain
  /// source-compatible; opening a remote filter on one reports a real error
  /// state instead of pretending the server returned no matches.
  Future<OptionsPage> searchFilterOptions(String filter, String query) {
    final source = this.source;
    if (source is! FilterOptionsDataSource) {
      throw UnsupportedError(
        'This data source does not implement FilterOptionsDataSource.',
      );
    }

    return (source as FilterOptionsDataSource).filterOptions(
      resource.key,
      filter: filter,
      query: query,
    );
  }

  Future<void> _fetchFirstPage({bool keepPrevious = false}) async {
    final requestId = ++_requestId;
    final preserve = keepPrevious && _status.isSuccess;

    if (!preserve) _status = LoadStatus.loading;
    _errorMessage = null;
    _isUnauthenticated = false;
    // A page-two fetch may still be in flight; it will drop its own result,
    // and clearing the flag here is what releases loadMore() again.
    _isLoadingMore = false;
    _loadMoreFailed = false;
    // Skeleton geometry: the screen renders fake cards while loading, so the
    // real records must not linger underneath and then jump.
    if (!preserve) {
      _records = const [];
      notifyListeners();
    }

    try {
      final page = await source.list(
        resource.key,
        page: 1,
        search: _searchTerm,
        sort: _activeSort?.key,
        direction: _activeSort?.direction,
        filters: _filters,
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
      _status = preserve && !_isUnauthenticated
          ? LoadStatus.success
          : LoadStatus.failure;
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
      final page = await source.list(
        resource.key,
        page: _page + 1,
        search: _searchTerm,
        sort: _activeSort?.key,
        direction: _activeSort?.direction,
        filters: _filters,
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

  /// Opens a drag-to-reorder session (P18): fetches the FULL, unpaginated
  /// list ordered by the resource's declared reorder column
  /// (`source.list(reorder: true)`), never the paginated rows already on
  /// screen — a drag has to be able to place a record anywhere in the whole
  /// set, not just within whichever page happened to be loaded. Sends the
  /// list's current [searchTerm] along — a term already active on the
  /// paginated list stays active once reorder mode opens, same as Filament.
  ///
  /// A fetch failure surfaces on [errorMessage] and leaves [isReordering]
  /// false — the screen stays on its normal list rather than opening a
  /// reorder view with nothing in it.
  Future<void> enterReorderMode() => _fetchReorderedPage();

  /// Shared by [enterReorderMode] and a [search] call made while already
  /// reordering. [_isReordering] is set true only on success — a failure
  /// here leaves it exactly as it was: still false for a fresh
  /// [enterReorderMode] call (never opens on nothing), still true for a
  /// searched refetch while already in the mode (stays open with
  /// [errorMessage] set, rather than being silently kicked back to the
  /// normal list).
  Future<void> _fetchReorderedPage() async {
    final requestId = ++_requestId;

    _errorMessage = null;
    notifyListeners();

    try {
      final page = await source.list(
        resource.key,
        reorder: true,
        search: _searchTerm,
        filters: _filters,
      );

      // Lost the race — [exitReorderMode]/[saveReorder] moved on (bumping
      // _requestId) while this was in flight, or a newer search superseded
      // it. Applying it now would either silently reopen reorder mode after
      // Cancel, or clobber a drag the user made after this search fired.
      if (requestId != _requestId) return;

      _reorderedRecords = page.records;
      // A search result IS the new rollback baseline — Filament reorders
      // within the filtered set too, so the positions [saveReorder] posts
      // (and a failed save's rollback) are always relative to whatever is
      // currently visible, searched or not.
      _serverReorderedRecords = page.records;
      _isReordering = true;
    } catch (e) {
      if (requestId != _requestId) return;

      _errorMessage = messageOf(e);
    }

    notifyListeners();
  }

  /// Moves one record from [oldIndex] to [newIndex] within
  /// [reorderedRecords], purely locally — no network call.
  ///
  /// Takes the FINAL target index — the index [oldIndex]'s item should have
  /// once it is already removed from the list. `ResourceListScreen` wires
  /// this straight onto `ReorderableListView.onReorderItem`, which passes
  /// exactly that (unlike the older, now-deprecated `onReorder`, whose
  /// `newIndex` is measured before the removal and needs an extra
  /// decrement); this method itself does no such adjustment, so it stays a
  /// plain list move that is trivial to unit test in isolation.
  ///
  /// A no-op while [isSavingReorder]: the drag order is already in flight to
  /// the server, and letting a drag land on top of it would move rows the
  /// in-flight POST doesn't know about — the screen also disables the
  /// handles visually, this is the state-layer guarantee behind that.
  ///
  /// Also bumps [_requestId], the same outrun-a-stale-fetch guard
  /// [exitReorderMode] and [saveReorder] use: a reorder-mode search fired
  /// before this drag and still in flight must not land afterwards and
  /// overwrite it — the drag the user is looking at now must win over a
  /// response describing an order from before it.
  void moveRecord(int oldIndex, int newIndex) {
    if (_isSavingReorder) return;

    ++_requestId;

    final updated = List<ResourceRecord>.of(_reorderedRecords);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    _reorderedRecords = updated;
    notifyListeners();
  }

  /// Commits the current drag order: `POST {resource}/reorder` with every
  /// record CURRENTLY VISIBLE's id, first entry first — the searched subset
  /// when a search term is active, same as [_fetchReorderedPage] fetched.
  /// This matches Filament's own reorder-while-filtered behavior: the server
  /// renumbers only the posted ids 1..N among themselves, leaving records
  /// outside the filter wherever they already were.
  ///
  /// Optimistic in the sense that the local order is already what the user
  /// sees — this call either confirms it (exit reorder mode, then
  /// [refresh] the normal paginated list so it reflects the new order) or
  /// rolls it back to the last server-confirmed order and surfaces
  /// [errorMessage], same as every other write in this package.
  Future<void> saveReorder() async {
    // Outruns any reorder-search fetch already in flight — its response must
    // not land on top of the order this save is about to commit.
    ++_requestId;
    _isSavingReorder = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await source.reorder(resource.key, [
        for (final record in _reorderedRecords) record.id,
      ]);
      _isSavingReorder = false;
      _isReordering = false;
      notifyListeners();
      await refresh();
    } catch (e) {
      _reorderedRecords = _serverReorderedRecords;
      _errorMessage = messageOf(e);
      _isSavingReorder = false;
      notifyListeners();
    }
  }

  /// Abandons the drag session with no write: restores the last
  /// server-confirmed order and closes reorder mode.
  void exitReorderMode() {
    // Outruns any reorder-search fetch already in flight — see [saveReorder]'s
    // own bump for why a late response must not reopen reorder mode after
    // Cancel.
    ++_requestId;
    _isReordering = false;
    _reorderedRecords = _serverReorderedRecords;
    _errorMessage = null;
    notifyListeners();
  }
}
