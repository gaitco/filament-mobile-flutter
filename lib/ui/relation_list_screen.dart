import 'dart:async';

import 'package:flutter/material.dart';

import '../data/relation_submit_target.dart';
import '../data/resource_record.dart';
import '../data/write_result.dart';
import '../ports/filament_file_picker.dart';
import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';
import '../schema/resource_schema.dart';
import '../state/relation_list_provider.dart';
import '../state/resource_form_provider.dart';
import 'material_panel_state_builder.dart';
import 'paginated_card_list.dart';
import 'resource_form_screen.dart';

/// One relation's full, paginated child rows — what `RelationSectionWidget`'s
/// "See all" opens.
///
/// A plain widget with no router dependency, like `ResourceListScreen`: the
/// host decides how it is reached. Shares that screen's skeleton
/// (`CardListSkeleton`) and scrolled, paginated body (`PaginatedCardList`) —
/// the endpoint serves the identical `{data, meta}` envelope — and adds only
/// the pieces that differ: the title and the scroll-triggered `loadMore()`.
///
/// Search and sort (P11) mirror `ResourceListScreen`'s chrome and gating: a
/// search field only when the descriptor's `search.enabled`, a sort menu only
/// when its `sorts` is non-empty — an undeclared relation, or a server
/// predating P11 (which parses as one), gets the plain list it always had.
/// The embedded `RelationSectionWidget` stays plain either way: the full
/// screen is where list controls live.
///
/// Row writes (P9): when [childResource] is passed — the host resolves it
/// from its already-loaded panel as `panel.resource(relation.resource)` — the
/// screen draws, per that resource's published `permissions` block, an Add
/// affordance (create), and per-row edit (update) and delete (delete). A
/// null [childResource] — a relation whose descriptor published no
/// `resource` key, an old server, or a host that never wired it — draws
/// nothing: absence means unavailable, never a control the server will 404.
/// The permissions come from the CHILD resource's own block, never invented
/// here; the server derives both from the same policies, so they cannot
/// disagree.
class RelationListScreen extends StatefulWidget {
  const RelationListScreen({
    required this.provider,
    this.childResource,
    this.stateBuilder,
    this.strings = const FilamentStrings(),
    this.onRecordTap,
    this.filePicker,
    super.key,
  });

  final RelationListProvider provider;

  /// The schema of the resource this relation's rows belong to — its `form`
  /// renders the row create/edit form, its `permissions` gate every write
  /// affordance. Null keeps the list read-only; see the class doc.
  final ResourceSchema? childResource;

  final PanelBodyBuilder? stateBuilder;
  final FilamentStrings strings;
  final void Function(ResourceRecord record)? onRecordTap;

  /// Forwarded to the row create/edit form, exactly as a host forwards it to
  /// `ResourceFormScreen` — without it a file field on the child form renders
  /// read-only, same as there.
  final FilamentFilePicker? filePicker;

  @override
  State<RelationListScreen> createState() => _RelationListScreenState();
}

class _RelationListScreenState extends State<RelationListScreen> {
  static const _debounce = Duration(milliseconds: 400);

  final _scroll = ScrollController();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // On the provider, not in build() — same reasoning as
    // ResourceListScreen: rebuilds happen inside the body's
    // ListenableBuilder, so build() runs once, against the skeleton.
    widget.provider.addListener(_scheduleFillCheck);
    // Only an untouched provider is loaded — same reasoning as
    // ResourceListScreen: a host-owned provider that already fetched keeps
    // its rows across a re-mount.
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

  /// Sibling of `ResourceListScreen._fillShortViewport`, for the same reason:
  /// a first page shorter than the viewport leaves nothing to scroll, so the
  /// scroll trigger alone strands the user on it.
  void _fillShortViewport(Duration _) {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent > 0) return;
    widget.provider.loadMore();
  }

  /// Debouncing lives here rather than in the provider — the same division
  /// `ResourceListScreen` documents: this is where the keystroke arrives.
  void _onSearchChanged(String term) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_debounce, () => widget.provider.search(term));
  }

  @override
  Widget build(BuildContext context) {
    final builder =
        widget.stateBuilder ?? materialPanelStateBuilder(widget.strings);

    return withPanelDirection(
      widget.provider.relation.direction,
      Scaffold(
        appBar: AppBar(
          title: Text(widget.provider.relation.label),
          actions: [
            // Both gated on the descriptor's published capability, never
            // drawn for an undeclared relation — see the class doc.
            if (widget.provider.relation.sorts.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.sort),
                onPressed: _openSortSheet,
                tooltip: widget.strings.sortTitle,
              ),
            // Drawn ONLY on the child resource's published `create` — see the
            // class doc for why a null childResource or a false flag gets no
            // button at all rather than a disabled one.
            if (widget.childResource?.permissions.create ?? false)
              IconButton(
                key: const ValueKey('relation.add'),
                icon: const Icon(Icons.add),
                tooltip: widget.strings.create,
                onPressed: () => _openForm(),
              ),
          ],
          bottom: widget.provider.relation.search.enabled
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextField(
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText:
                            widget.provider.relation.search.placeholder ??
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
      ),
    );
  }

  PanelViewState _state() {
    final provider = widget.provider;

    // `initial` belongs with `loading` — the first frame runs before the
    // post-frame load(), and treating it as anything else flashes the empty
    // state before the rows arrive.
    if (provider.status.isLoading || provider.status.isInitial) {
      return const PanelData(content: CardListSkeleton());
    }

    if (provider.status.isFailure) {
      final message = provider.errorMessage ?? widget.strings.relationFailed;
      // A 403 lands here with the server's own message — a permission
      // statement, not the empty-list statement below. Distinguished the
      // same way ResourceListScreen tells a signed-out 401 apart from a
      // generic failure.
      if (provider.isUnauthenticated) {
        return PanelUnauthenticated(message: message, retry: provider.load);
      }
      return PanelFailure(message: message, retry: provider.load);
    }

    if (provider.records.isEmpty) {
      return PanelEmpty(message: widget.strings.relationEmpty);
    }

    return PanelData(content: _list());
  }

  Widget _list() {
    final provider = widget.provider;

    return PaginatedCardList(
      records: provider.records,
      layout: provider.relation.card,
      isLoadingMore: provider.isLoadingMore,
      loadMoreFailed: provider.loadMoreFailed,
      loadMoreErrorMessage: provider.errorMessage,
      retryLabel: widget.strings.retry,
      onRefresh: provider.refresh,
      onLoadMoreRetry: provider.loadMore,
      controller: _scroll,
      onRecordTap: widget.onRecordTap,
      rowTrailing: _hasRowAffordances ? _rowTrailing : null,
    );
  }

  /// True when the child resource published at least one per-row permission.
  /// Computed once for the list rather than per row: the block is
  /// resource-level (per-ROW permissions stay uncomputed, the resource-list
  /// rule — a denied row discovers it on tap with the server's 403).
  bool get _hasRowAffordances {
    final permissions = widget.childResource?.permissions;
    return (permissions?.update ?? false) || (permissions?.delete ?? false);
  }

  Widget? _rowTrailing(ResourceRecord record) {
    final permissions = widget.childResource?.permissions;
    if (permissions == null) return null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (permissions.update)
          IconButton(
            key: const ValueKey('relation.row.edit'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: widget.strings.edit,
            visualDensity: VisualDensity.compact,
            onPressed: () => _openForm(record: record),
          ),
        if (permissions.delete)
          IconButton(
            key: const ValueKey('relation.row.delete'),
            icon: const Icon(Icons.delete_outline),
            tooltip: widget.strings.deleteConfirm,
            visualDensity: VisualDensity.compact,
            onPressed: () => _confirmDelete(record),
          ),
      ],
    );
  }

  /// Pushes the CHILD resource's form — create when [record] is null, edit
  /// otherwise — submitting to the relation endpoint through
  /// [RelationSubmitTarget] rather than to the child resource's own
  /// endpoints. The screen is `ResourceFormScreen` itself, not a fork: only
  /// the provider's write target differs.
  ///
  /// The awaited push is also the refresh trigger: a saved row changed this
  /// page's membership, and `refresh()` — the reload the provider already
  /// owns — is the cheapest correct response whether the form was saved or
  /// abandoned (a back-out costs one harmless re-fetch).
  ///
  /// The provider is built HERE and disposed in the `finally`, not inline in
  /// the route's `builder`. Two reasons, and the second is the leak:
  /// `builder` runs again on any route rebuild, so a fresh provider would
  /// replace the live one mid-edit; and `ResourceFormScreen` does not own what
  /// it is handed, so nothing else would ever dispose it. Only
  /// `ResourceFormProvider.dispose()` cancels the 400 ms `/state` debounce, so
  /// backing out of a row's form just after typing left a timer to fire
  /// against a provider nobody was listening to, and every Add or Edit tap
  /// leaked one notifier for the life of this screen.
  Future<void> _openForm({ResourceRecord? record}) async {
    final child = widget.childResource;
    // Fail-closed like the affordances: no published child resource, no form.
    if (child == null) return;

    final formProvider = ResourceFormProvider(
      source: widget.provider.source,
      resource: child,
      strings: widget.strings,
      recordId: record?.id,
      submitTarget: RelationSubmitTarget(
        resourceKey: widget.provider.resourceKey,
        recordId: widget.provider.id,
        relation: widget.provider.relation,
      ),
    );

    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => ResourceFormScreen(
            provider: formProvider,
            filePicker: widget.filePicker,
          ),
        ),
      );
    } finally {
      // In a `finally` so a push that throws still cleans up. Safe the instant
      // the route is popped: the provider guards its own post-disposal
      // notifications with `_disposed`, so an in-flight submit that lands
      // after this settles quietly instead of calling a dead notifier.
      formProvider.dispose();
    }

    widget.provider.refresh();
  }

  /// The record delete flow from `ResourceViewScreen`, one level down: same
  /// strings, same confirmation, same outcome mapping. Success needs nothing
  /// here — `RelationListProvider.delete` has already refreshed the page.
  Future<void> _confirmDelete(ResourceRecord record) async {
    // NOT `Directionality.of(context)` — this `State`'s own `context` is an
    // ANCESTOR of the `Directionality` `build()` wraps around the `Scaffold`;
    // see `textDirectionOf`'s doc (`material_panel_state_builder.dart`).
    final direction = textDirectionOf(widget.provider.relation.direction);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: direction,
        child: AlertDialog(
          title: Text(widget.strings.deleteConfirmTitle),
          content: Text(widget.strings.deleteConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(widget.strings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(widget.strings.deleteConfirm),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await widget.provider.delete(record.id);
    if (!mounted) return;

    switch (result) {
      case WriteSuccess() || WriteGone():
        break;
      case WriteDenied(:final message) || WriteFailed(:final message):
        _showMessage(message);
      // A delete request carries nothing to be invalid — this arm exists only
      // because the switch is exhaustive over the sealed type, not because
      // the server can send it here.
      case WriteInvalid():
        _showMessage(widget.strings.saveFailed);
    }
  }

  void _showMessage(String message) {
    // No `Directionality` wrap, for the reason `ResourceViewScreen` gives: a
    // SnackBar renders inside the Scaffold's own stack, under the
    // `withPanelDirection` wrap, and inherits the panel's direction already.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// `ResourceListScreen._openSortSheet` verbatim, one level down — same
  /// sheet, same `Directionality` reasoning, reading the relation's sorts.
  Future<void> _openSortSheet() async {
    final provider = widget.provider;
    // NOT `Directionality.of(context)`: this `State`'s own `context` is an
    // ANCESTOR of the `Directionality` `build()` wraps around the `Scaffold`
    // — see `textDirectionOf`'s doc. Resolved straight from the descriptor
    // value instead, which is also the value the sheet needs to inherit
    // anyway (`showModalBottomSheet` opens a route in the Navigator's
    // overlay, a sibling of this screen, not a descendant of it).
    final direction = textDirectionOf(provider.relation.direction);

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
              for (final sort in provider.relation.sorts)
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
