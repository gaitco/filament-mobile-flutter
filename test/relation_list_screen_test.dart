import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/relation_list_provider.dart';
import 'package:filament_mobile/ui/resource_card.dart';
import 'package:filament_mobile/ui/relation_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_until_found.dart';

const _relation = RelationDescriptor(
  key: 'tags',
  label: 'Tags',
  card: CardLayout(titleField: 'name'),
);

/// A [ResourceDataSource] whose `relation()` serves distinct rows per page,
/// so a pagination test actually proves paging rather than asserting against
/// one page repeated or an empty array. Every other method throws —
/// `RelationListScreen` never touches them.
class _Source implements ResourceDataSource {
  _Source({this.pagesOfRows = const [], this.error, this.failPage});

  /// Row payloads, one list per page. `pagesOfRows.length` is the last page.
  final List<List<Map<String, dynamic>>> pagesOfRows;
  final Object? error;

  /// The page number to fail on, page 1 still succeeding — a `loadMore()`
  /// failure over rows already on screen, which is the only state that
  /// renders the retry row.
  final int? failPage;

  final List<int> requestedPages = [];

  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
  }) async {
    requestedPages.add(page);
    if (error != null) throw error!;
    if (page == failPage) {
      throw FilamentTransportException('page $page failed', statusCode: 500);
    }

    final rows = pagesOfRows[page - 1];
    return PaginatedRecords(
      records: [
        for (final row in rows)
          ResourceRecord.fromJson(row, relation.recordKey),
      ],
      meta: PageMeta(
        currentPage: page,
        lastPage: pagesOfRows.length,
        perPage: rows.length,
        total: pagesOfRows.fold(0, (sum, rows) => sum + rows.length),
      ),
    );
  }

  @override
  Future<PanelSchema> panel() async => throw UnimplementedError();

  @override
  Future<PanelSchema?> cachedPanel() async => null;

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) => throw UnimplementedError();

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) =>
      throw UnimplementedError();

  @override
  Future<WriteResult> create(String resourceKey, Map<String, dynamic> values) =>
      throw UnimplementedError();

  @override
  Future<WriteResult> update(
    String resourceKey,
    Object id,
    Map<String, dynamic> values,
  ) => throw UnimplementedError();

  @override
  Future<WriteResult> destroy(String resourceKey, Object id) =>
      throw UnimplementedError();

  @override
  Future<ActionResult> runAction(
    String resourceKey,
    Object id,
    String action,
  ) => throw UnimplementedError();

  @override
  Future<OptionsPage> options(
    String resourceKey, {
    required String field,
    Object? recordId,
    required Map<String, dynamic> values,
    required String query,
  }) => throw UnimplementedError();

  @override
  Future<List<SchemaComponent>> state(
    String resourceKey, {
    Object? recordId,
    required Map<String, dynamic> values,
    required String changed,
  }) => throw UnimplementedError();

  @override
  Future<DashboardData> dashboard() => throw UnimplementedError();

  @override
  Future<UploadResult> uploadFile(
    String resourceKey,
    String field, {
    required List<int> bytes,
    required String filename,
  }) => throw UnimplementedError();
}

Widget _screenFor(
  _Source source, {
  void Function(ResourceRecord)? onRecordTap,
}) {
  return MaterialApp(
    home: RelationListScreen(
      provider: RelationListProvider(
        source: source,
        resourceKey: 'banners',
        id: 7,
        relation: _relation,
      ),
      onRecordTap: onRecordTap,
    ),
  );
}

void main() {
  testWidgets('shows the relation label as the screen title', (tester) async {
    await tester.pumpWidget(
      _screenFor(
        _Source(
          pagesOfRows: [
            [
              {'id': 1, 'name': 'Sale'},
            ],
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Tags'), findsOneWidget);
  });

  testWidgets(
    'the loading skeleton shows real card content, not six blank cards',
    (tester) async {
      // This relation's own card layout (`titleField: 'name'`, see
      // `_relation` above) does not match `ResourceRecord.fake()`'s
      // attributes (`title`/`subtitle`/`meta`) — exactly the mismatch that
      // shipped six visually blank skeleton cards in the P6d Task 8 review.
      // Asserted on the very first frame, before `load()` even fires (same
      // moment `ResourceListScreen`'s sibling "first frame" test checks) —
      // `initial` renders the skeleton too, so there is no fetch to race.
      await tester.pumpWidget(_screenFor(_Source(pagesOfRows: const [[]])));

      expect(find.byType(ResourceCard), findsNWidgets(6));
      expect(find.text('——————'), findsNWidgets(6));

      await tester.pumpAndSettle();
    },
  );

  testWidgets('paginates through the relation endpoint', (tester) async {
    // Two pages of DISTINCT rows, and page 1 alone (20 rows) is large enough
    // to overflow the test viewport — a test scrolling a one-row list would
    // drag nothing and prove nothing about paging.
    final source = _Source(
      pagesOfRows: [
        [
          for (var i = 0; i < 20; i++) {'id': i, 'name': 'Row $i'},
        ],
        [
          {'id': 999, 'name': 'Page two row'},
        ],
      ],
    );

    await tester.pumpWidget(_screenFor(source));
    await pumpUntilFound(tester, find.text('Row 0'));

    expect(find.text('Page two row'), findsNothing);
    expect(source.requestedPages, [1]);

    // Drag the list to trigger the scroll-pagination threshold, then let the
    // page-2 fetch resolve.
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await pumpUntilFound(tester, find.text('Page two row'));

    // The outgoing query genuinely carries the page number, not a repeat of
    // page 1 or a client-side slice of one big response. (Row 0 has since
    // scrolled off screen and `ListView.builder` culls it — this only
    // checks what actually reached the server and what is now visible.)
    expect(source.requestedPages, [1, 2]);
    expect(find.text('Page two row'), findsOneWidget);
  });

  testWidgets('offers a retry when the next page fails, keeping page one', (
    tester,
  ) async {
    // Sibling to `ResourceListScreen`'s identical test, and added for the
    // same reason: mutating `loadMoreFailed: provider.loadMoreFailed` to
    // `false` on EITHER screen left the whole suite green, so the retry
    // affordance was wired but never asserted to be wired.
    final source = _Source(
      pagesOfRows: [
        [
          for (var i = 0; i < 20; i++) {'id': i, 'name': 'Row $i'},
        ],
        [
          {'id': 999, 'name': 'Page two row'},
        ],
      ],
      failPage: 2,
    );

    await tester.pumpWidget(_screenFor(source));
    await pumpUntilFound(tester, find.text('Row 0'));

    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await pumpUntilFound(tester, find.byKey(const ValueKey('loadMore.failed')));

    expect(source.requestedPages, [1, 2]);
    expect(find.textContaining('page 2 failed'), findsOneWidget);
    expect(find.byType(ResourceCard), findsWidgets);
  });

  testWidgets('a 403 renders as a permission message, not an empty list', (
    tester,
  ) async {
    // An empty list says "there is nothing here" — a different, false
    // statement from "you may not see this". The server distinguishes
    // them (a 403, not a 200 with zero rows), so the client must too.
    final source = _Source(
      error: const FilamentTransportException(
        'This action is unauthorized.',
        statusCode: 403,
      ),
    );

    await tester.pumpWidget(_screenFor(source));
    await tester.pumpAndSettle();

    expect(find.text('This action is unauthorized.'), findsOneWidget);
    expect(find.text(const FilamentStrings().relationEmpty), findsNothing);
    expect(find.byKey(const ValueKey('panel.empty')), findsNothing);
  });

  testWidgets('shows empty when the relation genuinely has no rows', (
    tester,
  ) async {
    await tester.pumpWidget(_screenFor(_Source(pagesOfRows: const [[]])));
    await tester.pumpAndSettle();

    expect(find.byType(ResourceCard), findsNothing);
    expect(find.text(const FilamentStrings().relationEmpty), findsOneWidget);
  });

  testWidgets('taps a card and reports the record', (tester) async {
    ResourceRecord? tapped;

    await tester.pumpWidget(
      _screenFor(
        _Source(
          pagesOfRows: [
            [
              {'id': 1, 'name': 'Sale'},
            ],
          ],
        ),
        onRecordTap: (record) => tapped = record,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ResourceCard).first);
    await tester.pumpAndSettle();

    expect(tapped!.id, 1);
  });
}
