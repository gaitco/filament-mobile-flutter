import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../schema/card_layout.dart';
import '../schema/resource_schema.dart';
import 'layout.dart';
import 'resource_card.dart';
import 'resource_row.dart';

/// The loading placeholder shared by every paginated card list in this
/// package: six faded [ResourceCard]s.
///
/// Deliberately built from [ResourceSchema.fake]'s own card layout, NEVER the
/// real list's layout — [ResourceRecord.fake] carries attributes keyed
/// `title`/`subtitle`/`meta` to match that fake layout's field names, and a
/// real resource's or relation's own layout resolves none of them, which is
/// what shipped as six visually blank cards the one time a caller was passed
/// the real layout here (P6d Task 8 review). Extracting this one widget makes
/// that particular drift a compile-time impossibility rather than a bug two
/// call sites each have to remember not to reintroduce.
class CardListSkeleton extends StatelessWidget {
  const CardListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = ResourceSchema.fake().card;

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: 6,
      itemBuilder: (context, index) => Opacity(
        opacity: 0.4,
        child: ResourceCard(layout: layout, record: ResourceRecord.fake(index)),
      ),
    );
  }
}

/// The scrolled, paginated card list shared by `ResourceListScreen` and
/// `RelationListScreen` once their provider has records to show: real cards
/// over pull-to-refresh, and a trailing row that is a spinner while the next
/// page is in flight or a retry prompt when it just failed.
///
/// The retry prompt is why [loadMoreFailed] and [onLoadMoreRetry] exist at
/// all: `ResourceListProvider`/`RelationListProvider` already kept whatever
/// was on screen on a `loadMore()` failure (the right call — losing a
/// scrolled list because page four timed out is worse than the missing
/// page), but the failure used to set an `errorMessage` nothing ever read,
/// which is a silent failure by another name. This is the one place both
/// screens' trailing row is built, so it is the one place that silence needed
/// fixing.
class PaginatedCardList extends StatelessWidget {
  const PaginatedCardList({
    required this.records,
    required this.layout,
    required this.isLoadingMore,
    required this.loadMoreFailed,
    required this.loadMoreErrorMessage,
    required this.retryLabel,
    required this.onRefresh,
    required this.onLoadMoreRetry,
    required this.controller,
    this.onRecordTap,
    this.rowTrailing,
    this.rowStyle = ListRowStyle.card,
    this.beforeRecords = const [],
    this.afterRecords = const [],
    this.header,
    this.selectedRecordId,
    super.key,
  });

  final List<ResourceRecord> records;
  final CardLayout layout;
  final bool isLoadingMore;

  /// `card` (the default) renders exactly what this widget always has —
  /// one [ResourceCard] per record. `row` renders [ResourceRow]s with a
  /// thin divider between them instead, for wide screens (P23).
  final ListRowStyle rowStyle;

  /// Widgets placed inside the same scrollable as the records. These are
  /// used by the public custom-widget slots; empty lists preserve the legacy
  /// item indexes and rendering exactly.
  final List<Widget> beforeRecords;
  final List<Widget> afterRecords;

  /// Pinned above the first row when set — typically a [ResourceRowHeader]
  /// in `row` style. Rendered as the list's own first item rather than a
  /// sticky overlay: simpler, and nothing here needs it to stay pinned
  /// while scrolling.
  final Widget? header;

  /// True right after the most recent `loadMore()` call failed — cleared by
  /// the provider as soon as another fetch (a retry, a fresh `load()`, a
  /// `refresh()`) is attempted, never by this widget.
  final bool loadMoreFailed;
  final String? loadMoreErrorMessage;

  /// The host's/screen's own `strings.retry` — this widget carries no
  /// `FilamentStrings` dependency of its own, the same way `ResourceCard`
  /// carries none.
  final String retryLabel;

  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMoreRetry;
  final ScrollController controller;
  final void Function(ResourceRecord record)? onRecordTap;

  /// The record whose row paints selected — `row` style only, a card has no
  /// selected state. `PanelShell`'s master pane sets this (P23).
  final Object? selectedRecordId;

  /// Builds a row's trailing widget (edit/delete affordances on a relation
  /// list — P9), or returns null for a row with none. Null itself — every
  /// resource list — renders exactly the cards this widget always has.
  final Widget? Function(ResourceRecord record)? rowTrailing;

  @override
  Widget build(BuildContext context) {
    final headerCount = header == null ? 0 : 1;
    final recordOffset = beforeRecords.length + headerCount;

    final listView = ListView.separated(
      controller: controller,
      // A list shorter than its viewport is otherwise not scrollable at
      // all, which makes the RefreshIndicator above impossible to pull —
      // refresh must work on a one-row list too.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount:
          beforeRecords.length +
          headerCount +
          records.length +
          afterRecords.length +
          (isLoadingMore || loadMoreFailed ? 1 : 0),
      // A thin divider between rows in `row` style — a table, not a stack
      // of cards. Cards already carry their own margin, so this stays
      // invisible there.
      separatorBuilder: (context, index) => rowStyle == ListRowStyle.row
          ? const Divider(height: 1)
          : const SizedBox.shrink(),
      itemBuilder: (context, index) {
        if (index < beforeRecords.length) return beforeRecords[index];

        if (header != null && index == beforeRecords.length) return header!;

        final recordIndex = index - recordOffset;
        if (recordIndex >= records.length) {
          final afterIndex = recordIndex - records.length;
          if (afterIndex < afterRecords.length) return afterRecords[afterIndex];
          return _trailingRow();
        }

        final record = records[recordIndex];
        final onTap = onRecordTap == null ? null : () => onRecordTap!(record);
        final trailing = rowTrailing?.call(record);

        return rowStyle == ListRowStyle.row
            ? ResourceRow(
                layout: layout,
                record: record,
                onTap: onTap,
                trailing: trailing,
                selected: record.id == selectedRecordId,
              )
            : ResourceCard(
                layout: layout,
                record: record,
                onTap: onTap,
                trailing: trailing,
              );
      },
    );

    final refreshIndicator = RefreshIndicator(
      onRefresh: onRefresh,
      child: listView,
    );

    return Scrollbar(
      controller: controller,
      thumbVisibility: !FilamentLayout.isCompact(context),
      child: refreshIndicator,
    );
  }

  Widget _trailingRow() {
    if (loadMoreFailed) {
      return Padding(
        key: const ValueKey('loadMore.failed'),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loadMoreErrorMessage != null)
                Text(loadMoreErrorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton(onPressed: onLoadMoreRetry, child: Text(retryLabel)),
            ],
          ),
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
