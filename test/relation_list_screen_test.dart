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
import 'package:filament_mobile/schema/resource_labels.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/relation_list_provider.dart';
import 'package:filament_mobile/ui/resource_card.dart';
import 'package:filament_mobile/ui/relation_list_screen.dart';
import 'package:filament_mobile/ui/resource_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_until_found.dart';

const _relation = RelationDescriptor(
  key: 'tags',
  label: 'Tags',
  card: CardLayout(titleField: 'name'),
);

/// The P11 shape: search enabled, two declared sorts with a default — what
/// the full screen (never the embedded section) draws its chrome from.
const _searchableRelation = RelationDescriptor(
  key: 'tags',
  label: 'Tags',
  card: CardLayout(titleField: 'name'),
  search: ResourceSearch(enabled: true),
  sorts: [
    ResourceSort(key: 'name', label: 'Name', isDefault: true),
    ResourceSort(key: 'created_at', label: 'Created', direction: 'desc'),
  ],
);

/// A [ResourceDataSource] whose `relation()` serves distinct rows per page,
/// so a pagination test actually proves paging rather than asserting against
/// one page repeated or an empty array. Every other method throws —
/// `RelationListScreen` never touches them.
class _Source implements ResourceDataSource {
  @override
  Future<void> reorder(String resourceKey, List<Object> ids) =>
      throw UnimplementedError();
  _Source({
    this.pagesOfRows = const [],
    this.error,
    this.failPage,
    this.writeResult = const WriteSuccess({}),
  });

  /// Row payloads, one list per page. `pagesOfRows.length` is the last page.
  final List<List<Map<String, dynamic>>> pagesOfRows;
  final Object? error;

  /// The page number to fail on, page 1 still succeeding — a `loadMore()`
  /// failure over rows already on screen, which is the only state that
  /// renders the retry row.
  final int? failPage;

  /// What the relation writes return; the delete flow tests drive both a
  /// success and a denial through it.
  final WriteResult writeResult;

  final List<int> requestedPages = [];

  /// The search/sort params the most recent `relation()` call carried (P11).
  String? lastSearch;
  String? lastSort;
  String? lastDirection;

  /// Which relation write fired, and the child id it carried — so a delete
  /// test asserts the ROW's key reached the endpoint, not just "a call".
  final List<String> writes = [];
  Object? lastChildId;

  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async {
    requestedPages.add(page);
    lastSearch = search;
    lastSort = sort;
    lastDirection = direction;
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
  Future<WriteResult> createRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Map<String, dynamic> values,
  ) async {
    writes.add('create');
    return writeResult;
  }

  @override
  Future<WriteResult> updateRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
    Map<String, dynamic> values,
  ) async {
    writes.add('update');
    lastChildId = childId;
    return writeResult;
  }

  @override
  Future<WriteResult> deleteRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
  ) async {
    writes.add('delete');
    lastChildId = childId;
    return writeResult;
  }

  /// The pushed row-edit form seeds itself from the CHILD resource's own
  /// record read — a real answer, not a throw, so the edit-flow test renders
  /// the form it pushed.
  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async =>
      ResourceRecord(id: id, attributes: const {'name': 'Sale'});

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
    bool reorder = false,
  }) => throw UnimplementedError();

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
  ResourceSchema? childResource,
  RelationDescriptor relation = _relation,
}) {
  return MaterialApp(
    home: RelationListScreen(
      provider: RelationListProvider(
        source: source,
        resourceKey: 'banners',
        id: 7,
        relation: relation,
      ),
      childResource: childResource,
      onRecordTap: onRecordTap,
    ),
  );
}

/// The relation rows' own resource — a one-field form, so the pushed row
/// form renders a real field, and a settable permissions block, which is
/// what every affordance gate reads.
ResourceSchema _childResource({
  ResourcePermissions permissions = const ResourcePermissions(),
  bool live = false,
}) => ResourceSchema(
  key: 'tags',
  labels: const ResourceLabels(singular: 'Tag', plural: 'Tags'),
  permissions: permissions,
  form: [
    SchemaComponent.fromJson({
      'type': 'text',
      'name': 'name',
      'label': 'Name',
      // `live` arms ResourceFormProvider's 400 ms `/state` debounce, which is
      // the timer the disposal test below needs in flight.
      if (live) 'live': true,
    }, 'form[0]'),
  ],
);

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

  testWidgets('fills a viewport page one leaves short by loading further pages '
      'unprompted', (tester) async {
    // Sibling to `ResourceListScreen`'s identical test — a short first
    // page leaves nothing to scroll, so the scroll trigger alone strands
    // the user on it.
    final source = _Source(
      pagesOfRows: [
        [
          {'id': 1, 'name': 'Sale'},
        ],
        [
          {'id': 2, 'name': 'Clearance'},
        ],
      ],
    );

    await tester.pumpWidget(_screenFor(source));
    await tester.pumpAndSettle();

    expect(source.requestedPages, [1, 2]);
    expect(find.text('Clearance'), findsOneWidget);
  });

  testWidgets('pull-to-refresh works on a list too short to scroll', (
    tester,
  ) async {
    final source = _Source(
      pagesOfRows: [
        [
          {'id': 1, 'name': 'Sale'},
        ],
      ],
    );

    await tester.pumpWidget(_screenFor(source));
    await tester.pumpAndSettle();
    expect(source.requestedPages, [1]);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(source.requestedPages, [1, 1]);
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

  group('search/sort chrome (P11)', () {
    const rows = [
      [
        {'id': 1, 'name': 'Sale'},
      ],
    ];

    testWidgets('draws a search field and sort button only when the '
        'descriptor publishes them', (tester) async {
      // Gated exactly like ResourceListScreen: an undeclared relation — or a
      // server predating P11, which parses as one — gets the plain list.
      await tester.pumpWidget(_screenFor(_Source(pagesOfRows: rows)));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.widgetWithIcon(IconButton, Icons.sort), findsNothing);

      await tester.pumpWidget(
        _screenFor(_Source(pagesOfRows: rows), relation: _searchableRelation),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithIcon(IconButton, Icons.sort), findsOneWidget);
    });

    testWidgets('debounces search into the provider rather than querying per '
        'keystroke', (tester) async {
      // Sibling to ResourceListScreen's identical test — the timer lives in
      // the screen for the same reason.
      final source = _Source(pagesOfRows: rows);

      await tester.pumpWidget(
        _screenFor(source, relation: _searchableRelation),
      );
      await tester.pumpAndSettle();

      final before = source.requestedPages.length;

      await tester.enterText(find.byType(TextField), 'sa');
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        source.requestedPages.length,
        before,
        reason: 'no query before the debounce',
      );

      await tester.enterText(find.byType(TextField), 'sal');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(source.requestedPages.length, before + 1);
      expect(source.lastSearch, 'sal');
      expect(source.requestedPages.last, 1);
    });

    testWidgets('picking a sort re-fetches page one with the new key', (
      tester,
    ) async {
      final source = _Source(pagesOfRows: rows);

      await tester.pumpWidget(
        _screenFor(source, relation: _searchableRelation),
      );
      await tester.pumpAndSettle();

      // The declared default is active from the very first fetch.
      expect(source.lastSort, 'name');
      expect(source.lastDirection, 'asc');

      await tester.tap(find.widgetWithIcon(IconButton, Icons.sort));
      await tester.pumpAndSettle();
      expect(find.text(const FilamentStrings().sortTitle), findsOneWidget);

      await tester.tap(find.text('Created'));
      await tester.pumpAndSettle();

      expect(source.lastSort, 'created_at');
      expect(source.lastDirection, 'desc');
      expect(source.requestedPages.last, 1);
    });
  });

  group('row-write affordances (P9)', () {
    const rows = [
      [
        {'id': 1, 'name': 'Sale'},
      ],
    ];

    testWidgets('Add is drawn on the child resource\'s published create, and '
        'pushes the child resource\'s form', (tester) async {
      await tester.pumpWidget(
        _screenFor(
          _Source(pagesOfRows: rows),
          childResource: _childResource(
            permissions: const ResourcePermissions(create: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('relation.add')));
      await tester.pumpAndSettle();

      expect(find.byType(ResourceFormScreen), findsOneWidget);
      // The CHILD resource's own form and label — reused whole, not a
      // relation-specific shape.
      expect(find.text('Tag'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
    });

    testWidgets('the form it pushes is DISPOSED on the way back, so a live '
        'field\'s /state debounce cannot fire after the pop', (tester) async {
      // The leak: the provider used to be built inline in the route's
      // `builder`, and `ResourceFormScreen` does not own what it is handed, so
      // nothing ever disposed it — one leaked notifier per Add/Edit tap, and
      // `dispose()` is the only thing that cancels the `/state` debounce.
      //
      // This fake's `state()` throws UnimplementedError, so a timer that
      // survives the pop fails this test by firing, not merely by lingering.
      await tester.pumpWidget(
        _screenFor(
          _Source(pagesOfRows: rows),
          childResource: _childResource(
            permissions: const ResourcePermissions(create: true),
            live: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('relation.add')));
      await tester.pumpAndSettle();

      final provider = tester
          .widget<ResourceFormScreen>(find.byType(ResourceFormScreen))
          .provider;

      // Type, then leave immediately — the debounce is armed and unfired.
      await tester.enterText(find.byType(TextField).first, 'typed');
      await tester.pump();

      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(ResourceFormScreen), findsNothing);
      // Already disposed, so disposing again trips ChangeNotifier's own
      // assertion — the only handle a test has on "was it disposed".
      expect(provider.dispose, throwsA(isA<Error>()));
    });

    testWidgets('no Add without a published create — and nothing at all '
        'without a child resource', (tester) async {
      await tester.pumpWidget(
        _screenFor(_Source(pagesOfRows: rows), childResource: _childResource()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('relation.add')), findsNothing);

      // A null childResource — the descriptor published no `resource` key,
      // or the host never resolved it — is the read-only shape: absence
      // means unavailable, never a control the server would 404.
      await tester.pumpWidget(_screenFor(_Source(pagesOfRows: rows)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('relation.add')), findsNothing);
      expect(find.byKey(const ValueKey('relation.row.edit')), findsNothing);
      expect(find.byKey(const ValueKey('relation.row.delete')), findsNothing);
    });

    testWidgets('row edit and delete follow update/delete independently', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screenFor(
          _Source(pagesOfRows: rows),
          childResource: _childResource(
            permissions: const ResourcePermissions(update: true, delete: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('relation.row.edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('relation.row.delete')), findsOneWidget);
      // create was not published, so no Add — the gates are independent.
      expect(find.byKey(const ValueKey('relation.add')), findsNothing);
    });

    testWidgets('a delete-only permission draws delete and no edit', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screenFor(
          _Source(pagesOfRows: rows),
          childResource: _childResource(
            permissions: const ResourcePermissions(delete: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('relation.row.edit')), findsNothing);
      expect(find.byKey(const ValueKey('relation.row.delete')), findsOneWidget);
    });

    testWidgets('row edit pushes the child form seeded from the child '
        'resource\'s record read', (tester) async {
      await tester.pumpWidget(
        _screenFor(
          _Source(pagesOfRows: rows),
          childResource: _childResource(
            permissions: const ResourcePermissions(update: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('relation.row.edit')));
      await tester.pumpAndSettle();

      expect(find.byType(ResourceFormScreen), findsOneWidget);
      // Seeded from the fake's record() — edit mode genuinely loaded.
      expect(find.text('Name'), findsOneWidget);
    });

    testWidgets('row delete asks first, then deletes through the relation '
        'endpoint and refreshes the page', (tester) async {
      final source = _Source(pagesOfRows: rows);

      await tester.pumpWidget(
        _screenFor(
          source,
          childResource: _childResource(
            permissions: const ResourcePermissions(delete: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('relation.row.delete')));
      await tester.pumpAndSettle();

      // The same confirmation as the record delete flow — nothing has fired
      // yet.
      expect(find.text('Delete this record?'), findsOneWidget);
      expect(source.writes, isEmpty);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(source.writes, ['delete']);
      expect(source.lastChildId, 1);
      // Page one re-fetched through the provider's own refresh.
      expect(source.requestedPages, [1, 1]);
    });

    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      final source = _Source(pagesOfRows: rows);

      await tester.pumpWidget(
        _screenFor(
          source,
          childResource: _childResource(
            permissions: const ResourcePermissions(delete: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('relation.row.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(source.writes, isEmpty);
      expect(source.requestedPages, [1]);
    });

    testWidgets('a denied delete surfaces the server\'s message and keeps '
        'the rows', (tester) async {
      final source = _Source(
        pagesOfRows: rows,
        writeResult: const WriteDenied('This action is unauthorized.'),
      );

      await tester.pumpWidget(
        _screenFor(
          source,
          childResource: _childResource(
            permissions: const ResourcePermissions(delete: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('relation.row.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('This action is unauthorized.'), findsOneWidget);
      // A denial changed nothing, so no re-fetch.
      expect(source.requestedPages, [1]);
      expect(find.text('Sale'), findsOneWidget);
    });
  });
}
