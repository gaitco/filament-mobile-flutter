import 'dart:async';

import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';
import '../schema/resource_schema.dart';
import '../state/resource_list_provider.dart';
import 'material_panel_state_builder.dart';
import 'paginated_card_list.dart';

/// A resource's records as a scrollable list of cards.
///
/// A plain widget with no router dependency: the host decides where a tap goes.
class ResourceListScreen extends StatefulWidget {
  const ResourceListScreen({
    required this.provider,
    this.stateBuilder,
    this.strings = const FilamentStrings(),
    this.onRecordTap,
    this.onCreateTap,
    super.key,
  });

  final ResourceListProvider provider;
  final PanelBodyBuilder? stateBuilder;
  final FilamentStrings strings;
  final void Function(ResourceRecord record)? onRecordTap;

  /// Called when the create affordance is tapped. The screen owns no create
  /// form of its own — same division as `onRecordTap` — so a host that never
  /// wires this up gets no create button at all, never one that renders and
  /// silently no-ops on tap.
  final VoidCallback? onCreateTap;

  @override
  State<ResourceListScreen> createState() => _ResourceListScreenState();
}

class _ResourceListScreenState extends State<ResourceListScreen> {
  static const _debounce = Duration(milliseconds: 400);

  final _scroll = ScrollController();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // On the provider, not in build(): rebuilds happen inside the body's
    // ListenableBuilder, so the State's own build() runs once — against the
    // skeleton, whose list never attaches [_scroll]. Each page landing is
    // what must re-check whether the viewport is still short.
    widget.provider.addListener(_scheduleFillCheck);
    // Only an untouched provider is loaded. The host owns the provider, so a
    // host that keeps one per resource would otherwise have its list blanked
    // and refetched every time the user came back from a record.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.provider.status.isInitial) widget.provider.load();
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    widget.provider.removeListener(_scheduleFillCheck);
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _scheduleFillCheck() {
    WidgetsBinding.instance.addPostFrameCallback(_fillShortViewport);
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent * 0.8) {
      widget.provider.loadMore();
    }
  }

  /// A first page shorter than the viewport leaves nothing to scroll, so
  /// [_onScroll] can never fire and the user is stranded on it. Checked after
  /// every build: each appended page notifies, rebuilds, and re-checks, until
  /// the list overflows or `hasMore` runs out. `loadMore()`'s own guards make
  /// the repeat calls free.
  void _fillShortViewport(Duration _) {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent > 0) return;
    widget.provider.loadMore();
  }

  /// Debouncing lives here rather than in the provider: this is where the
  /// keystroke arrives, and a provider owning a timer is untestable without
  /// pumping fake async.
  void _onSearchChanged(String term) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_debounce, () => widget.provider.search(term));
  }

  @override
  Widget build(BuildContext context) {
    final builder =
        widget.stateBuilder ?? materialPanelStateBuilder(widget.strings);

    return withPanelDirection(
      widget.provider.resource.direction,
      Scaffold(
        appBar: AppBar(
          title: Text(widget.provider.resource.labels.plural),
          actions: [
            if (widget.provider.resource.sorts.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.sort),
                onPressed: _openSortSheet,
                tooltip: widget.strings.sortTitle,
              ),
          ],
          bottom: widget.provider.resource.search.enabled
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextField(
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText:
                            widget.provider.resource.search.placeholder ??
                            widget.strings.searchHint,
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                )
              : null,
        ),
        body: ListenableBuilder(
          listenable: widget.provider,
          builder: (context, _) => builder(context, _state()),
        ),
        floatingActionButton: _createButton(),
      ),
    );
  }

  /// Gated on the **resource**-level block: capability, not authorization.
  /// There is no per-record question to ask here — nothing is being created
  /// yet — so the resource's `permissions.create` is the only signal there is.
  ///
  /// Also gated on `onCreateTap != null`: a host that never wired it must get
  /// no button, never one that renders enabled and silently no-ops on tap.
  Widget? _createButton() {
    if (!widget.provider.resource.permissions.create) return null;
    if (widget.onCreateTap == null) return null;

    return FloatingActionButton(
      key: const ValueKey('resource.create'),
      tooltip: widget.strings.create,
      onPressed: () => widget.onCreateTap?.call(),
      child: const Icon(Icons.add),
    );
  }

  PanelViewState _state() {
    final provider = widget.provider;

    // `initial` belongs with `loading`: the first frame runs before the
    // post-frame load(), and treating it as anything else flashes the empty
    // state before the records arrive.
    if (provider.status.isLoading || provider.status.isInitial) {
      return const PanelData(content: CardListSkeleton());
    }

    if (provider.status.isFailure) {
      final message = provider.errorMessage ?? widget.strings.loadFailed;
      // Distinguished so a signed-out user is told they were signed out,
      // not that the server is broken — see PanelUnauthenticated's doc.
      if (provider.isUnauthenticated) {
        return PanelUnauthenticated(message: message, retry: provider.load);
      }
      return PanelFailure(message: message, retry: provider.load);
    }

    if (provider.records.isEmpty) {
      return PanelEmpty(message: widget.strings.empty);
    }

    return PanelData(content: _list());
  }

  Widget _list() {
    final provider = widget.provider;

    return PaginatedCardList(
      records: provider.records,
      layout: provider.resource.card,
      isLoadingMore: provider.isLoadingMore,
      loadMoreFailed: provider.loadMoreFailed,
      loadMoreErrorMessage: provider.errorMessage,
      retryLabel: widget.strings.retry,
      onRefresh: provider.refresh,
      onLoadMoreRetry: provider.loadMore,
      controller: _scroll,
      onRecordTap: widget.onRecordTap,
    );
  }

  Future<void> _openSortSheet() async {
    final provider = widget.provider;
    // NOT `Directionality.of(context)`: this `State`'s own `context` is an
    // ANCESTOR of the `Directionality` `build()` wraps around the `Scaffold`
    // — see `textDirectionOf`'s doc. Resolved straight from the schema
    // value instead, which is also the value the sheet needs to inherit
    // anyway (`showModalBottomSheet` opens a route in the Navigator's
    // overlay, a sibling of this screen, not a descendant of it).
    final direction = textDirectionOf(provider.resource.direction);

    final chosen = await showModalBottomSheet<ResourceSort>(
      context: context,
      builder: (sheetContext) => Directionality(
        textDirection: direction,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.strings.sortTitle,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final sort in provider.resource.sorts)
                ListTile(
                  title: Text(sort.label),
                  selected: sort.key == provider.activeSort?.key,
                  onTap: () => Navigator.of(sheetContext).pop(sort),
                ),
            ],
          ),
        ),
      ),
    );

    if (chosen != null) await provider.sortBy(chosen);
  }
}
