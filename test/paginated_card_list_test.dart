import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/ui/paginated_card_list.dart';
import 'package:filament_mobile/ui/resource_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exact placeholder text `ResourceRecord.fake()` carries — asserting
/// this text is on screen is the one thing the P6d Task 8 review's finding
/// says would have caught it: a loading state of six visually BLANK cards
/// still passes a test that only checks `findsNWidgets(6)` on `ResourceCard`,
/// because a blank card is still a `ResourceCard`. This constant is the
/// assertion that fails when the fields don't actually resolve.
const _placeholderTitle = '——————';

const _layout = CardLayout(titleField: 'name');

void main() {
  group('CardListSkeleton', () {
    testWidgets(
      'shows real card content — not six blank cards — built from its own '
      'fake layout, regardless of what real layout the surrounding screen '
      'would otherwise use',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: CardListSkeleton())),
        );

        expect(find.byType(ResourceCard), findsNWidgets(6));
        // Every card, not just one — the whole skeleton is built from the
        // fake layout, never a caller-supplied one.
        expect(find.text(_placeholderTitle), findsNWidgets(6));
      },
    );
  });

  group('PaginatedCardList', () {
    Widget harness({
      bool isLoadingMore = false,
      bool loadMoreFailed = false,
      String? loadMoreErrorMessage,
      VoidCallback? onLoadMoreRetry,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: PaginatedCardList(
            records: [
              ResourceRecord.fromJson({'id': 1, 'name': 'Sale'}, 'id'),
            ],
            layout: _layout,
            isLoadingMore: isLoadingMore,
            loadMoreFailed: loadMoreFailed,
            loadMoreErrorMessage: loadMoreErrorMessage,
            retryLabel: 'Retry',
            onRefresh: () async {},
            onLoadMoreRetry: onLoadMoreRetry ?? () {},
            controller: ScrollController(),
          ),
        ),
      );
    }

    testWidgets('shows a spinner in the trailing row while loading more', (
      tester,
    ) async {
      await tester.pumpWidget(harness(isLoadingMore: true));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('loadMore.failed')), findsNothing);
    });

    testWidgets(
      'shows the failure message and a retry button instead of a spinner '
      'when the last loadMore() failed — a silent dead write is what this '
      'guards against',
      (tester) async {
        var retried = 0;

        await tester.pumpWidget(
          harness(
            loadMoreFailed: true,
            loadMoreErrorMessage: 'تعذّر',
            onLoadMoreRetry: () => retried++,
          ),
        );

        expect(find.byKey(const ValueKey('loadMore.failed')), findsOneWidget);
        expect(find.text('تعذّر'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.tap(find.text('Retry'));

        expect(retried, 1);
      },
    );

    testWidgets('no trailing row at all once there is nothing more to load', (
      tester,
    ) async {
      await tester.pumpWidget(harness());

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('loadMore.failed')), findsNothing);
    });
  });
}
