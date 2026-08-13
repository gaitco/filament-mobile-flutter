import 'package:flutter/material.dart';

import '../data/paginated_records.dart';
import '../data/resource_record.dart';
import '../ports/filament_strings.dart';
import '../schema/relation_descriptor.dart';
import '../state/load_status.dart';
import '../state/resource_view_provider.dart';
import 'resource_card.dart';

/// One published relation, rendered on the record-detail screen as a
/// labelled section: the relation's label, its first page of rows, and a
/// "See all" affordance when the relation holds more than that page. The full
/// paginated screen that affordance opens is [RelationListScreen].
///
/// Fetches its own first page independently of the record's own load, via
/// [fetch] — bound by the caller (`ResourceViewScreen`) to
/// `ResourceViewProvider.loadRelation`, the same read path every other list
/// in this package uses, so there is nothing a host has to wire for a
/// published relation to render. One section's slow or failing endpoint
/// never blocks or blanks its siblings, because each owns its own request
/// and its own loading/empty/failure state.
///
/// Zero rows and an absent relation are different statements and must not
/// look the same: this widget renders whenever the server published the
/// relation (see `ResourceViewScreen`, which builds one section per entry in
/// `resource.relations`), and shows [FilamentStrings.relationEmpty] rather
/// than nothing when a real, successful load comes back with no rows.
///
/// A failed load degrades to [FilamentStrings.relationFailed], never an
/// infinite spinner — the pilot recorded in `docs/superpowers/HANDOFF.md`
/// once shipped a permanent spinner for a load that "succeeded" against a
/// resource the signed-in user could not see. This widget's `catch` — which
/// wraps only the `await fetch()`, never the trivial field reads after it —
/// is what keeps that from happening again.
class RelationSectionWidget extends StatefulWidget {
  const RelationSectionWidget({
    required this.relation,
    required this.recordId,
    required this.fetch,
    this.parent,
    this.strings = const FilamentStrings(),
    this.onSeeAllTap,
    super.key,
  });

  final RelationDescriptor relation;

  /// The parent record's id, carried through to [onSeeAllTap] — this widget
  /// never sends it anywhere itself; [fetch] is already bound to it by the
  /// caller.
  final Object recordId;

  /// Loads one page of this relation, already parsed — bound by the caller to
  /// `ResourceViewProvider.loadRelation`. [page] defaults to 1 here (this
  /// section only ever shows the first page); `RelationListScreen` reuses the
  /// same signature to page further.
  final Future<PaginatedRecords> Function({int page}) fetch;

  /// The provider holding the record this section hangs off (P9). When it
  /// finishes a reload — a record action that changed relation membership is
  /// the case that motivated this — the section re-fetches its rows through
  /// [fetch], so stale membership never survives the action that changed it.
  /// Null keeps the load-once-in-initState behaviour: a caller without the
  /// provider (a test, a host composing the widget itself) loses the refresh,
  /// nothing else.
  final ResourceViewProvider? parent;

  final FilamentStrings strings;

  /// Called with [relation] and [recordId] when "See all" is tapped. A host
  /// that never wires this up gets no button at all — absence means
  /// unavailable, never a rendered control that silently no-ops on tap.
  final void Function(RelationDescriptor relation, Object recordId)?
  onSeeAllTap;

  @override
  State<RelationSectionWidget> createState() => _RelationSectionWidgetState();
}

class _RelationSectionWidgetState extends State<RelationSectionWidget> {
  LoadStatus _status = LoadStatus.initial;
  List<ResourceRecord> _records = const [];
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    widget.parent?.addListener(_onParentReloaded);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(RelationSectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A swapped provider leaves the old subscription dead on arrival: the new
    // one would never be heard and the old one would fire into a widget that
    // no longer follows it.
    if (oldWidget.parent != widget.parent) {
      oldWidget.parent?.removeListener(_onParentReloaded);
      widget.parent?.addListener(_onParentReloaded);
    }
  }

  @override
  void dispose() {
    widget.parent?.removeListener(_onParentReloaded);
    super.dispose();
  }

  /// Reloads only once the parent's reload has COMPLETED. The provider
  /// notifies twice per load — once going `loading`, once settling — and
  /// fetching on the first would race the record the rows belong to. This is
  /// a listener callback, not a build: [_load] sets state asynchronously,
  /// never during a build phase.
  void _onParentReloaded() {
    if (widget.parent?.status.isSuccess ?? false) _load();
  }

  Future<void> _load() async {
    setState(() => _status = LoadStatus.loading);

    final PaginatedRecords page;
    try {
      // `fetch()` parses as part of resolving — `RestResourceDataSource
      // .relation()` builds every `ResourceRecord` before this `await`
      // returns — so a client-side parse bug (e.g. a row missing its
      // `recordKey`) throws from inside this `try` exactly like a network
      // failure does, and both land on the same [FilamentStrings.relationFailed]
      // below. That is a deliberate trade, not an oversight: distinguishing
      // them would mean this widget parsing the envelope itself again, and
      // `ResourceListProvider._fetchFirstPage()` already accepts the same
      // conflation for `list()`, whose parsing lives inside `await
      // _source.list(...)` the same way. A parse bug is a package defect the
      // test suite should catch before it ships, not a distinction the user
      // on screen needs — either way there is nothing they can do but leave
      // and come back, so one message is honest, not a missing feature.
      page = await widget.fetch();
    } catch (_) {
      // Never rethrown, and never left `loading`: a thrown error here is
      // exactly the shape of the incident this widget exists to prevent —
      // see the class doc.
      if (!mounted) return;
      setState(() => _status = LoadStatus.failure);
      return;
    }

    if (!mounted) return;
    setState(() {
      _records = page.records;
      _hasMore = page.meta.hasMore;
      _status = LoadStatus.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // Generous above, tight below: the heading belongs to the rows under
      // it, and a symmetric gap made a section float between the block above
      // and its own content. Grouping by proximity is what makes a screen of
      // stacked cards read as sections rather than as a wall of slabs.
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.relation.label,
                // A section heading has to outrank the card titles beneath
                // it. At `titleMedium` it sat at the same weight as the rows
                // it was naming, so nothing on the screen led.
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.3,
                ),
              ),
              // `onSeeAllTap != null` is part of the gate, not just the
              // handler: a host that never wired it must get no button, never
              // one that renders enabled and silently no-ops on tap.
              if (_status.isSuccess && _hasMore && widget.onSeeAllTap != null)
                TextButton(
                  key: const ValueKey('relation.seeAll'),
                  onPressed: () => widget.onSeeAllTap?.call(
                    widget.relation,
                    widget.recordId,
                  ),
                  child: Text(widget.strings.seeAll),
                ),
            ],
          ),
          _body(),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_status) {
      case LoadStatus.initial:
      case LoadStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        );
      case LoadStatus.failure:
        return Padding(
          key: const ValueKey('relation.failed'),
          padding: const EdgeInsets.all(12),
          child: Text(widget.strings.relationFailed),
        );
      case LoadStatus.success:
        if (_records.isEmpty) {
          return Padding(
            key: const ValueKey('relation.empty'),
            padding: const EdgeInsets.all(12),
            child: Text(widget.strings.relationEmpty),
          );
        }
        return Column(
          children: [
            for (final record in _records)
              ResourceCard(layout: widget.relation.card, record: record),
          ],
        );
    }
  }
}
