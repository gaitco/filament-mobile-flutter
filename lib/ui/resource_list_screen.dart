import 'dart:async';

import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';
import '../schema/resource_schema.dart';
import '../state/resource_list_provider.dart';
import 'layout.dart';
import 'material_panel_state_builder.dart';
import 'paginated_card_list.dart';
import 'resource_card.dart';
import 'resource_row.dart';

/// A resource's records as a scrollable list of cards.
///
/// A plain widget with no router dependency: the host decides where a tap goes.
///
/// **Reorder toggle gating (P18):** shown iff `resource.reorder != null` —
/// capability alone, no host hook required. This is deliberately unlike
/// [onCreateTap]: that control needs a host because navigating to a create
/// form is host-owned UI the package cannot build for it, so an unwired host
/// gets no button at all rather than one that silently no-ops. Reordering has
/// no such gap — the write (`ResourceDataSource.reorder`) lives entirely
/// inside this package's own data layer, with no navigation or host-owned
/// screen involved, so there is nothing a host could fail to wire up.
class ResourceListScreen extends StatefulWidget {
  const ResourceListScreen({
    required this.provider,
    this.stateBuilder,
    this.strings = const FilamentStrings(),
    this.onRecordTap,
    this.onCreateTap,
    this.rowStyle,
    this.selectedRecordId,
    super.key,
  });

  final ResourceListProvider provider;
  final PanelBodyBuilder? stateBuilder;
  final FilamentStrings strings;
  final void Function(ResourceRecord record)? onRecordTap;

  /// Overrides the form-factor-driven default (P23): null resolves to
  /// `row` at the expanded form factor and `card` everywhere else —
  /// compact AND medium both keep today's cards, since a table only earns
  /// its columns once there's width to spare for them.
  final ListRowStyle? rowStyle;

  /// Called when the create affordance is tapped. The screen owns no create
  /// form of its own — same division as `onRecordTap` — so a host that never
  /// wires this up gets no create button at all, never one that renders and
  /// silently no-ops on tap.
  final VoidCallback? onCreateTap;

  /// Highlights one row in `row` style — see [PaginatedCardList.selectedRecordId].
  final Object? selectedRecordId;

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
    _searchTimer = Timer(_debounce, () => _search(term));
  }

  /// While reordering, a failed search leaves the mode open with
  /// [ResourceListProvider.errorMessage] set but nothing rendering it — the
  /// list underneath just keeps showing whatever it last had. Routed through
  /// [_runShowingReorderError], the same helper [_enterReorderMode] and
  /// [_saveReorder] use. The NORMAL (non-reordering) search is left exactly
  /// as it was: its own failure already renders inline in the resource's
  /// body state, so snackbarring it too would be a duplicate.
  Future<void> _search(String term) {
    final provider = widget.provider;

    return provider.isReordering
        ? _runShowingReorderError(() => provider.search(term))
        : provider.search(term);
  }

  @override
  Widget build(BuildContext context) {
    final builder =
        widget.stateBuilder ?? materialPanelStateBuilder(widget.strings);

    return withPanelDirection(
      widget.provider.resource.direction,
      ListenableBuilder(
        listenable: widget.provider,
        builder: (context, _) {
          final provider = widget.provider;
          final reordering = provider.isReordering;

          return Scaffold(
            appBar: AppBar(
              title: Text(provider.resource.labels.plural),
              actions: [
                if (!reordering && provider.resource.sorts.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.sort),
                    onPressed: _openSortSheet,
                    tooltip: widget.strings.sortTitle,
                  ),
                if (reordering)
                  IconButton(
                    key: const ValueKey('resource.reorder.cancel'),
                    icon: const Icon(Icons.close),
                    tooltip: widget.strings.cancelReordering,
                    // Disabled while a save is in flight: cancelling out from
                    // under a POST that is already committing the drag order
                    // would abandon the mode with a write the server may still
                    // apply, the same in-flight guard moveRecord() and the
                    // drag handles below already give the drag itself.
                    onPressed: provider.isSavingReorder
                        ? null
                        : provider.exitReorderMode,
                  ),
                if (_reorderAction() case final action?) action,
              ],
              // Search stays available in both modes — the reorder toggle
              // does not touch this bar's bottom slot at all.
              bottom: provider.resource.search.enabled
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(56),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: TextField(
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText:
                                provider.resource.search.placeholder ??
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
            // Swapped wholesale rather than nested: a ReorderableListView
            // inside the same scroll viewport as RefreshIndicator/ListView
            // fights both pull-to-refresh and its own drag gestures.
            body: reordering
                ? _reorderList(context)
                : builder(context, _state(context)),
            floatingActionButton: reordering ? null : _createButton(),
          );
        },
      ),
    );
  }

  /// The AppBar's reorder toggle/Done action — null when the resource
  /// declares no [ReorderConfig] at all, per this screen's class doc.
  Widget? _reorderAction() {
    final provider = widget.provider;
    if (provider.resource.reorder == null) return null;

    if (!provider.isReordering) {
      return IconButton(
        key: const ValueKey('resource.reorder.toggle'),
        icon: const Icon(Icons.swap_vert),
        tooltip: widget.strings.reorderRecords,
        onPressed: _enterReorderMode,
      );
    }

    return TextButton(
      key: const ValueKey('resource.reorder.done'),
      onPressed: provider.isSavingReorder ? null : _saveReorder,
      child: provider.isSavingReorder
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(widget.strings.doneReordering),
    );
  }

  /// A failed entry leaves [ResourceListProvider.isReordering] false — the
  /// screen falls back to the normal list, per that method's own doc — but
  /// [ResourceListProvider.errorMessage] was still set and nothing rendered
  /// it: the toggle press just silently did nothing from the user's side.
  Future<void> _enterReorderMode() =>
      _runShowingReorderError(widget.provider.enterReorderMode);

  Future<void> _saveReorder() =>
      _runShowingReorderError(widget.provider.saveReorder);

  /// Awaits a reorder-mode write/fetch, then snackbars whatever
  /// [ResourceListProvider.errorMessage] it left behind — success always
  /// clears that field first, so a non-null value here is always this
  /// call's own failure, never a stale one from something earlier.
  Future<void> _runShowingReorderError(Future<void> Function() action) async {
    await action();

    if (!mounted) return;
    if (widget.provider.errorMessage case final message?) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty ? widget.strings.reorderFailed : message,
          ),
        ),
      );
    }
  }

  /// Explicit drag handles (`buildDefaultDragHandles: false`) pinned to the
  /// LEADING edge via [ReorderableDragStartListener] wrapped in a plain
  /// [Row] — the ambient [Directionality] this screen already establishes
  /// (see [build]'s `withPanelDirection` wrap) puts that first child at the
  /// start, which is the right edge under RTL with no `EdgeInsetsDirectional`
  /// math of its own needed beyond the handle's own padding.
  Widget _reorderList(BuildContext context) {
    final provider = widget.provider;
    final style = _resolvedRowStyle(context);

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.all(8),
      itemCount: provider.reorderedRecords.length,
      // `onReorderItem`, not the deprecated `onReorder`: this callback's
      // `newIndex` already accounts for the dragged item's own removal, which
      // is exactly what `ResourceListProvider.moveRecord` expects — see that
      // method's doc.
      onReorderItem: provider.moveRecord,
      itemBuilder: (context, index) {
        final record = provider.reorderedRecords[index];

        return Padding(
          key: ValueKey(record.id),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                // Mirrors moveRecord()'s own in-flight guard visually: a
                // handle a user can still drag while the save it already
                // triggered is in flight would let a NEW drag land on top of
                // an order the server hasn't confirmed yet.
                enabled: !provider.isSavingReorder,
                child: const Padding(
                  padding: EdgeInsetsDirectional.only(start: 4, end: 12),
                  child: Icon(Icons.drag_handle),
                ),
              ),
              Expanded(
                child: style == ListRowStyle.row
                    ? ResourceRow(
                        layout: provider.resource.card,
                        record: record,
                      )
                    : ResourceCard(
                        layout: provider.resource.card,
                        record: record,
                      ),
              ),
            ],
          ),
        );
      },
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

  /// Resolves `card`/`row` when the host didn't pin one: `card` on a phone,
  /// `row` on anything wider.
  ///
  /// Medium kept cards until the screenshots showed what that costs — a card
  /// at 800dp leaves the right half of every row empty, because a card's
  /// fields stack for a width it no longer has. Rows were held back only
  /// because four columns used to squeeze at that width; now that they shed
  /// instead (see `resource_row.dart`), the width objection is gone.
  ListRowStyle _resolvedRowStyle(BuildContext context) =>
      widget.rowStyle ??
      (FilamentLayout.isCompact(context)
          ? ListRowStyle.card
          : ListRowStyle.row);

  PanelViewState _state(BuildContext context) {
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

    return PanelData(content: _list(context));
  }

  Widget _list(BuildContext context) {
    final provider = widget.provider;
    final style = _resolvedRowStyle(context);

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
      rowStyle: style,
      header: style == ListRowStyle.row
          ? ResourceRowHeader(layout: provider.resource.card)
          : null,
      onRecordTap: widget.onRecordTap,
      selectedRecordId: widget.selectedRecordId,
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
