import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';
import '../state/relation_list_provider.dart';
import 'material_panel_state_builder.dart';
import 'paginated_card_list.dart';

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
class RelationListScreen extends StatefulWidget {
  const RelationListScreen({
    required this.provider,
    this.stateBuilder,
    this.strings = const FilamentStrings(),
    this.onRecordTap,
    super.key,
  });

  final RelationListProvider provider;
  final PanelBodyBuilder? stateBuilder;
  final FilamentStrings strings;
  final void Function(ResourceRecord record)? onRecordTap;

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
        appBar: AppBar(title: Text(widget.provider.relation.label)),
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
    );
  }
}
