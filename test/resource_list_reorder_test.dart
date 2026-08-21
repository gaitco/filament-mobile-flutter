// P18 Task 6, Step 1: `ResourceListProvider`'s reorder-mode state, and
// `ResourceListScreen`'s reorder toggle/ReorderableListView/Done wiring.
// Provider-level and widget-level tests share this file rather than
// splitting: the reorder feature is one seam end to end, and the same
// `_ReorderSource` fake drives both halves.

import 'dart:async';

import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/schema/resource_labels.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/resource_list_provider.dart';
import 'package:filament_mobile/ui/resource_card.dart';
import 'package:filament_mobile/ui/resource_list_screen.dart';
import 'package:filament_mobile/ui/resource_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [ResourceDataSource] whose `list()` and `reorder()` alone answer —
/// every other method throws, same "throw unless a test needs it" shape the
/// rest of this suite's fakes use.
class _ReorderSource implements ResourceDataSource {
  _ReorderSource({
    this.records = const [],
    this.searchedRecords,
    this.reorderError,
    this.listError,
  });

  List<ResourceRecord> records;

  /// Returned instead of [records] for a `reorder: true` call carrying a
  /// non-empty [search] — lets a test simulate the server narrowing the
  /// reorder-ordered list, the way a real search would.
  List<ResourceRecord>? searchedRecords;
  Object? reorderError;

  /// Thrown by every `reorder: true` `list()` call when set — lets a test
  /// simulate a failed `enterReorderMode()`/in-mode search fetch, as
  /// distinct from [reorderError] on the `POST .../reorder` write. Scoped to
  /// the reorder-mode fetch only, not the screen's own normal-mode `load()`
  /// on mount, which would otherwise throw the same error into the ordinary
  /// list body and confuse a test with two renderings of one message.
  Object? listError;

  int reorderCalls = 0;
  List<Object>? lastOrder;
  int normalListCalls = 0;
  int reorderListCalls = 0;

  /// The `search` argument on the most recent `reorder: true` call — null if
  /// none has happened yet, `''` for one made with no term.
  String? lastReorderSearch;

  /// Awaited before `list()` returns, when set — lets a test hold a
  /// reorder-mode fetch open to race it against a later `exitReorderMode()`
  /// or `moveRecord()` call, the same shape [reorderGate] already gives
  /// `reorder()`.
  Future<void>? listGate;

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
    bool reorder = false,
  }) async {
    if (reorder && listError != null) throw listError!;

    List<ResourceRecord> rows;
    if (reorder) {
      reorderListCalls++;
      lastReorderSearch = search;
      rows = (search != null && search.isNotEmpty && searchedRecords != null)
          ? searchedRecords!
          : records;
    } else {
      normalListCalls++;
      rows = records;
    }

    if (listGate != null) await listGate;

    return PaginatedRecords(
      records: rows,
      meta: PageMeta(
        currentPage: 1,
        lastPage: 1,
        perPage: rows.length,
        total: rows.length,
      ),
    );
  }

  /// Awaited before `reorder()` returns, when set — lets a test hold a
  /// `saveReorder()` call open to observe `isSavingReorder` mid-flight.
  Future<void>? reorderGate;

  @override
  Future<void> reorder(String resourceKey, List<Object> ids) async {
    reorderCalls++;
    lastOrder = ids;
    if (reorderGate != null) await reorderGate;
    if (reorderError != null) throw reorderError!;
  }

  @override
  Future<PanelSchema> panel() async => throw UnimplementedError();

  @override
  Future<PanelSchema?> cachedPanel() async => null;

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async =>
      throw UnimplementedError();

  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async => throw UnimplementedError();

  @override
  Future<WriteResult> createRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Map<String, dynamic> values,
  ) => throw UnimplementedError();

  @override
  Future<WriteResult> updateRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
    Map<String, dynamic> values,
  ) => throw UnimplementedError();

  @override
  Future<WriteResult> deleteRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
  ) => throw UnimplementedError();

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

List<ResourceRecord> _abc() => [
  const ResourceRecord(id: 'A'),
  const ResourceRecord(id: 'B'),
  const ResourceRecord(id: 'C'),
];

ResourceSchema _reorderable({bool canCreate = false}) => ResourceSchema(
  key: 'slides',
  labels: const ResourceLabels(singular: 'Slide', plural: 'Slides'),
  permissions: ResourcePermissions(create: canCreate),
  sorts: const [ResourceSort(key: 'name', label: 'Name', isDefault: true)],
  reorder: const ReorderConfig(column: 'position', direction: 'asc'),
);

ResourceSchema get _notReorderable => const ResourceSchema(
  key: 'posts',
  labels: ResourceLabels(singular: 'Post', plural: 'Posts'),
);

void main() {
  group('ResourceListProvider reorder mode (P18)', () {
    test(
      'enterReorderMode() fetches via list(reorder: true) and opens the mode',
      () async {
        final source = _ReorderSource(records: _abc());
        final provider = ResourceListProvider(
          source: source,
          resource: _reorderable(),
        );

        await provider.enterReorderMode();

        expect(provider.isReordering, isTrue);
        expect(provider.reorderedRecords.map((r) => r.id), ['A', 'B', 'C']);
        expect(source.reorderListCalls, 1);
      },
    );

    test('moveRecord(0, 2) on [A,B,C] yields [B,C,A]', () async {
      final provider = ResourceListProvider(
        source: _ReorderSource(records: _abc()),
        resource: _reorderable(),
      );
      await provider.enterReorderMode();

      provider.moveRecord(0, 2);

      expect(provider.reorderedRecords.map((r) => r.id), ['B', 'C', 'A']);
    });

    test('saveReorder() calls reorder() once with the dragged order, then '
        'refreshes and exits reorder mode', () async {
      final source = _ReorderSource(records: _abc());
      final provider = ResourceListProvider(
        source: source,
        resource: _reorderable(),
      );
      await provider.enterReorderMode();
      provider.moveRecord(0, 2); // [B, C, A]

      await provider.saveReorder();

      expect(source.reorderCalls, 1);
      expect(source.lastOrder, ['B', 'C', 'A']);
      expect(provider.isReordering, isFalse);
      // refresh() after a successful save re-fetches the normal paginated
      // list — never the reorder-mode one.
      expect(source.normalListCalls, 1);
    });

    test('a failed saveReorder() restores the pre-drag server order and sets '
        'errorMessage, without leaving reorder mode', () async {
      final source = _ReorderSource(
        records: _abc(),
        reorderError: Exception('boom'),
      );
      final provider = ResourceListProvider(
        source: source,
        resource: _reorderable(),
      );
      await provider.enterReorderMode();
      provider.moveRecord(0, 2); // [B, C, A]

      await provider.saveReorder();

      expect(provider.reorderedRecords.map((r) => r.id), ['A', 'B', 'C']);
      expect(provider.errorMessage, isNotNull);
      expect(
        provider.isReordering,
        isTrue,
        reason:
            'a failed save keeps the drag session open so the user can '
            'retry, rather than silently dropping them back to the '
            'read-only list',
      );
    });

    test('exitReorderMode() discards the drag and closes the mode', () async {
      final provider = ResourceListProvider(
        source: _ReorderSource(records: _abc()),
        resource: _reorderable(),
      );
      await provider.enterReorderMode();
      provider.moveRecord(0, 2);

      provider.exitReorderMode();

      expect(provider.isReordering, isFalse);
      expect(provider.reorderedRecords.map((r) => r.id), ['A', 'B', 'C']);
    });

    // Fix round (code review): search must be FUNCTIONAL in reorder mode,
    // not a silently no-op control — Filament keeps its own search filter
    // active while reordering, and the screen's own class doc already
    // argues against an enabled control that does nothing.

    test(
      'enterReorderMode() sends the search term already active on the list',
      () async {
        final source = _ReorderSource(records: _abc());
        final provider = ResourceListProvider(
          source: source,
          resource: _reorderable(),
        );
        await provider.search('foo'); // normal-mode search first

        await provider.enterReorderMode();

        expect(source.lastReorderSearch, 'foo');
      },
    );

    test('search() while reordering refetches reorder=1 with the term, never '
        'the paginated list', () async {
      final searched = [const ResourceRecord(id: 'B')];
      final source = _ReorderSource(records: _abc(), searchedRecords: searched);
      final provider = ResourceListProvider(
        source: source,
        resource: _reorderable(),
      );
      await provider.enterReorderMode();

      await provider.search('b');

      expect(source.reorderListCalls, 2);
      expect(source.lastReorderSearch, 'b');
      expect(source.normalListCalls, 0);
      expect(provider.reorderedRecords.map((r) => r.id), ['B']);
      expect(provider.isReordering, isTrue);
    });

    test('a failed save after searching in reorder mode rolls back to the '
        'SEARCHED baseline, not the original unsearched one', () async {
      final searched = [const ResourceRecord(id: 'B')];
      final source = _ReorderSource(records: _abc(), searchedRecords: searched);
      final provider = ResourceListProvider(
        source: source,
        resource: _reorderable(),
      );
      await provider.enterReorderMode(); // baseline [A, B, C]
      await provider.search('b'); // new baseline [B]
      source.reorderError = Exception('boom');

      await provider.saveReorder();

      expect(provider.reorderedRecords.map((r) => r.id), ['B']);
    });

    test('moveRecord() is a no-op while a save is already in flight', () async {
      final source = _ReorderSource(records: _abc());
      // Never completes on its own — lets the test observe the
      // in-flight state before resolving it.
      final gate = Completer<void>();
      source.reorderGate = gate.future;
      final provider = ResourceListProvider(
        source: source,
        resource: _reorderable(),
      );
      await provider.enterReorderMode();

      final saving = provider.saveReorder();
      expect(provider.isSavingReorder, isTrue);

      provider.moveRecord(0, 2);
      expect(
        provider.reorderedRecords.map((r) => r.id),
        ['A', 'B', 'C'],
        reason:
            'a drag landing mid-save must not move rows the in-flight '
            'POST does not know about',
      );

      gate.complete();
      await saving;
    });

    // Fix round (final review): a slow reorder-mode fetch racing a LATER
    // call — see ResourceListProvider._requestId's doc. Both tests gate
    // list() so the stale response is still in flight when the later call
    // lands, then release it and prove the response was dropped.

    test('a late reorder-search response after Cancel does not reopen reorder '
        'mode', () async {
      final source = _ReorderSource(records: _abc());
      final provider = ResourceListProvider(
        source: source,
        resource: _reorderable(),
      );
      await provider.enterReorderMode();

      final gate = Completer<void>();
      source.listGate = gate.future;
      final searching = provider.search('foo'); // in flight, gated
      source.listGate = null; // don't gate the fetches below

      provider.exitReorderMode();
      expect(provider.isReordering, isFalse);

      gate.complete();
      await searching;

      expect(
        provider.isReordering,
        isFalse,
        reason:
            'the search fetch that outlived Cancel must not reopen the '
            'mode Cancel already closed',
      );
    });

    test('a late reorder-search response after a drag does not discard the '
        'drag', () async {
      final searched = [const ResourceRecord(id: 'A')];
      final source = _ReorderSource(records: _abc(), searchedRecords: searched);
      final provider = ResourceListProvider(
        source: source,
        resource: _reorderable(),
      );
      await provider.enterReorderMode(); // baseline [A, B, C]

      final gate = Completer<void>();
      source.listGate = gate.future;
      final searching = provider.search('a'); // in flight, gated
      source.listGate = null;

      provider.moveRecord(0, 2); // drag lands while the search is in flight
      expect(provider.reorderedRecords.map((r) => r.id), ['B', 'C', 'A']);

      gate.complete();
      await searching;

      expect(
        provider.reorderedRecords.map((r) => r.id),
        ['B', 'C', 'A'],
        reason:
            'the search response that outlived the drag must not '
            'overwrite it',
      );
    });
  });

  group('ResourceListScreen reorder toggle (P18)', () {
    testWidgets(
      'the toggle is absent when the resource carries no reorder capability',
      (tester) async {
        final provider = ResourceListProvider(
          source: _ReorderSource(records: _abc()),
          resource: _notReorderable,
        );

        await tester.pumpWidget(
          MaterialApp(home: ResourceListScreen(provider: provider)),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('resource.reorder.toggle')),
          findsNothing,
        );
      },
    );

    testWidgets('the toggle is present when resource.reorder is set', (
      tester,
    ) async {
      final provider = ResourceListProvider(
        source: _ReorderSource(records: _abc()),
        resource: _reorderable(),
      );

      await tester.pumpWidget(
        MaterialApp(home: ResourceListScreen(provider: provider)),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('resource.reorder.toggle')),
        findsOneWidget,
      );
    });

    testWidgets(
      'tapping the toggle enters reorder mode, hides sort and create, and '
      'renders one drag handle per record',
      (tester) async {
        final source = _ReorderSource(records: _abc());
        final provider = ResourceListProvider(
          source: source,
          resource: _reorderable(canCreate: true),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ResourceListScreen(provider: provider, onCreateTap: () {}),
          ),
        );
        await tester.pump();
        expect(find.byIcon(Icons.sort), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('resource.reorder.toggle')));
        await tester.pumpAndSettle();

        expect(provider.isReordering, isTrue);
        expect(find.byType(ReorderableDragStartListener), findsNWidgets(3));
        expect(find.byIcon(Icons.sort), findsNothing);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(
          find.byKey(const ValueKey('resource.reorder.done')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'at 1200 wide (expanded) reorder mode shows drag handles on rows, '
      'and moveRecord still fires (P23)',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final source = _ReorderSource(records: _abc());
        final provider = ResourceListProvider(
          source: source,
          resource: _reorderable(),
        );

        await tester.pumpWidget(
          MaterialApp(home: ResourceListScreen(provider: provider)),
        );
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('resource.reorder.toggle')));
        await tester.pumpAndSettle();

        expect(provider.isReordering, isTrue);
        expect(find.byType(ReorderableDragStartListener), findsNWidgets(3));
        expect(find.byType(ResourceRow), findsNWidgets(3));
        expect(find.byType(ResourceCard), findsNothing);

        provider.moveRecord(0, 2);
        expect(provider.reorderedRecords.map((r) => r.id).toList(), [
          'B',
          'C',
          'A',
        ]);
      },
    );

    testWidgets('Done triggers saveReorder() and closes reorder mode', (
      tester,
    ) async {
      final source = _ReorderSource(records: _abc());
      final provider = ResourceListProvider(
        source: source,
        resource: _reorderable(),
      );

      await tester.pumpWidget(
        MaterialApp(home: ResourceListScreen(provider: provider)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('resource.reorder.toggle')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('resource.reorder.done')));
      await tester.pumpAndSettle();

      expect(source.reorderCalls, 1);
      expect(provider.isReordering, isFalse);
      expect(find.byKey(const ValueKey('resource.reorder.done')), findsNothing);
    });

    testWidgets(
      'a failed Done shows the server message and stays in reorder mode',
      (tester) async {
        final source = _ReorderSource(
          records: _abc(),
          reorderError: Exception('تعذّر الحفظ'),
        );
        final provider = ResourceListProvider(
          source: source,
          resource: _reorderable(),
        );

        await tester.pumpWidget(
          MaterialApp(home: ResourceListScreen(provider: provider)),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('resource.reorder.toggle')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('resource.reorder.done')));
        await tester.pumpAndSettle();

        expect(provider.isReordering, isTrue);
        expect(find.text('تعذّر الحفظ'), findsOneWidget);
      },
    );

    testWidgets(
      'Cancel (close icon) exits reorder mode without calling reorder()',
      (tester) async {
        final source = _ReorderSource(records: _abc());
        final provider = ResourceListProvider(
          source: source,
          resource: _reorderable(),
        );

        await tester.pumpWidget(
          MaterialApp(home: ResourceListScreen(provider: provider)),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('resource.reorder.toggle')));
        await tester.pumpAndSettle();
        provider.moveRecord(0, 2); // drag something, then abandon it

        await tester.tap(find.byKey(const ValueKey('resource.reorder.cancel')));
        await tester.pumpAndSettle();

        expect(provider.isReordering, isFalse);
        expect(source.reorderCalls, 0);
        expect(
          find.byKey(const ValueKey('resource.reorder.cancel')),
          findsNothing,
        );
      },
    );

    // Fix round (final review): a failed enterReorderMode() sets
    // errorMessage but leaves isReordering false — the toggle press
    // previously just did nothing visible.
    testWidgets(
      'a failed reorder-mode entry shows the server message via a SnackBar',
      (tester) async {
        final source = _ReorderSource(
          records: _abc(),
          listError: Exception('تعذّر فتح الترتيب'),
        );
        final provider = ResourceListProvider(
          source: source,
          resource: _reorderable(),
        );

        await tester.pumpWidget(
          MaterialApp(home: ResourceListScreen(provider: provider)),
        );
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('resource.reorder.toggle')));
        await tester.pumpAndSettle();

        expect(provider.isReordering, isFalse);
        expect(find.text('تعذّر فتح الترتيب'), findsOneWidget);
        // Still the read-only list — never opened on nothing.
        expect(
          find.byKey(const ValueKey('resource.reorder.toggle')),
          findsOneWidget,
        );
      },
    );
  });
}
