import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../schema/card_layout.dart';
import '../schema/resource_schema.dart';
import 'resource_card.dart';

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
    super.key,
  });

  final List<ResourceRecord> records;
  final CardLayout layout;
  final bool isLoadingMore;

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

  /// Builds a row's trailing widget (edit/delete affordances on a relation
  /// list — P9), or returns null for a row with none. Null itself — every
  /// resource list — renders exactly the cards this widget always has.
  final Widget? Function(ResourceRecord record)? rowTrailing;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: controller,
        // A list shorter than its viewport is otherwise not scrollable at
        // all, which makes the RefreshIndicator above impossible to pull —
        // refresh must work on a one-row list too.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        itemCount: records.length + (isLoadingMore || loadMoreFailed ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= records.length) return _trailingRow();

          final record = records[index];

          return ResourceCard(
            layout: layout,
            record: record,
            onTap: onRecordTap == null ? null : () => onRecordTap!(record),
            trailing: rowTrailing?.call(record),
          );
        },
      ),
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
