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
/// No search field, no sort button: `RelationDescriptor` carries no
/// `search`/`sorts` block, so there is nothing to build them from.
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
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Only an untouched provider is loaded — same reasoning as
    // ResourceListScreen: a host-owned provider that already fetched keeps
    // its rows across a re-mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.provider.status.isInitial) widget.provider.load();
    });
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent * 0.8) {
      widget.provider.loadMore();
    }
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
  Future<void> _openForm({ResourceRecord? record}) async {
    final child = widget.childResource;
    // Fail-closed like the affordances: no published child resource, no form.
    if (child == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ResourceFormScreen(
          provider: ResourceFormProvider(
            source: widget.provider.source,
            resource: child,
            strings: widget.strings,
            recordId: record?.id,
            submitTarget: RelationSubmitTarget(
              resourceKey: widget.provider.resourceKey,
              recordId: widget.provider.id,
              relation: widget.provider.relation,
            ),
          ),
          filePicker: widget.filePicker,
        ),
      ),
    );

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
}
