import 'package:flutter/material.dart';

import '../data/paginated_records.dart';
import '../data/resource_record.dart';
import '../ports/filament_strings.dart';
import '../schema/relation_descriptor.dart';
import '../state/load_status.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.relation.label, style: theme.textTheme.titleMedium),
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
