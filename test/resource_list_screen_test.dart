import 'dart:async';

import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/ports/filament_event_transport.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/resource_list_provider.dart';
import 'package:filament_mobile/ui/filter_sheet.dart';
import 'package:filament_mobile/ui/resource_card.dart';
import 'package:filament_mobile/ui/resource_list_screen.dart';
import 'package:filament_mobile/ui/resource_row.dart';
import 'package:filament_mobile/ui/widget_slots.dart';
import 'package:flutter/material.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source implements ResourceDataSource {
  @override
  Future<void> reorder(String resourceKey, List<Object> ids) =>
      throw UnimplementedError();
  _Source({this.error, this.rows = 2, this.pages = 1, this.failPage});

  final Object? error;
  final int rows;

  /// How many pages the resource has. Left at 1, `hasMore` is false and
  /// `loadMore()` returns immediately — which is why every pagination
  /// assertion needs this set, and why one that forgets it passes against
  /// nothing.
  final int pages;

  /// The page number to fail on, page 1 still succeeding: a `loadMore()`
  /// failure over rows already on screen, which is the only state that
  /// renders the retry row.
  final int? failPage;

  int listCalls = 0;
  String? lastSearch;
  Map<String, Object?> lastFilters = const {};
  final List<int> requestedPages = [];

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
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
    bool reorder = false,
    Map<String, Object?> filters = const {},
  }) async {
    listCalls++;
    lastSearch = search;
    lastFilters = filters;
    requestedPages.add(page);
    if (error != null) throw error!;
    if (page == failPage) throw Exception('تعذّر تحميل الصفحة $page');

    // Distinct rows per page: a paging assertion against one page repeated
    // proves nothing about paging.
    final offset = (page - 1) * rows;

    return PaginatedRecords(
      records: [
        for (var i = offset; i < offset + rows; i++)
          ResourceRecord.fromJson({'id': i, 'name': 'صف $i'}, 'id'),
      ],
      meta: PageMeta(
        currentPage: page,
        lastPage: pages,
        perPage: 20,
        total: rows * pages,
      ),
    );
  }

  @override
  Future<PanelSchema> panel() async => throw UnimplementedError();

  @override
  Future<PanelSchema?> cachedPanel() async => null;

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async =>
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

class _EventTransport implements FilamentEventTransport {
  final controller = StreamController<RealtimeEvent>.broadcast(sync: true);

  @override
  Stream<RealtimeEvent> events(String channel) => controller.stream;
}

ResourceSchema get _resource => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'لافتة', 'plural': 'اللافتات'},
  'recordKey': 'id',
  'card': {
    'title': {'field': 'name'},
  },
  'search': {'enabled': true, 'placeholder': 'ابحث'},
  'sorts': [
    {'key': 'name', 'label': 'الاسم', 'default': true},
  ],
}, 'r');

Widget _screenFor(
  _Source source, {
  void Function(ResourceRecord)? onRecordTap,
  ListRowStyle? rowStyle,
  FilamentWidgetRegistry? widgetRegistry,
}) {
  return MaterialApp(
    home: ResourceListScreen(
      provider: ResourceListProvider(source: source, resource: _resource),
      onRecordTap: onRecordTap,
      rowStyle: rowStyle,
      widgetRegistry: widgetRegistry,
    ),
  );
}

/// Pins a phone-sized viewport for the tests that describe the card shape.
///
/// The binding's own 800x600 default is `medium`, which renders rows since
/// P23's default flipped — so a test that means "a card per record" has to
/// say which width it means rather than inherit one. Tests left unpinned
/// exercise the row shape at 800, which is the real default there now.
void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('custom widgets render in order with typed resource scope', (
    tester,
  ) async {
    usePhone(tester);
    final registry = FilamentWidgetRegistry();
    ResourceListWidgetScope? receivedScope;
    registry
      ..register(FilamentWidgetSlot.resourceListBeforeContent, (
        context,
        scope,
      ) {
        receivedScope = scope as ResourceListWidgetScope;
        return const Text('custom before one');
      })
      ..register(
        FilamentWidgetSlot.resourceListBeforeContent,
        (context, scope) => const Text('custom before two'),
      )
      ..register(
        FilamentWidgetSlot.resourceListBeforeContent,
        (context, scope) => null,
      )
      ..register(
        FilamentWidgetSlot.resourceListAfterContent,
        (context, scope) => const Text('custom after'),
      );

    await tester.pumpWidget(
      _screenFor(_Source(rows: 1), widgetRegistry: registry),
    );
    await tester.pumpAndSettle();

    expect(receivedScope?.resource.key, 'banners');
    expect(find.text('custom before one'), findsOneWidget);
    expect(find.text('custom before two'), findsOneWidget);
    expect(find.text('custom after'), findsOneWidget);

    final beforeOne = tester.getTopLeft(find.text('custom before one')).dy;
    final beforeTwo = tester.getTopLeft(find.text('custom before two')).dy;
    final record = tester.getTopLeft(find.byType(ResourceCard)).dy;
    final after = tester.getTopLeft(find.text('custom after')).dy;
    expect(beforeOne, lessThan(beforeTwo));
    expect(beforeTwo, lessThan(record));
    expect(record, lessThan(after));
  });

  testWidgets('a custom list widget can be the content of an empty resource', (
    tester,
  ) async {
    final registry = FilamentWidgetRegistry()
      ..registerWidget(
        FilamentWidgetSlot.resourceListBeforeContent,
        const Text('host-owned empty state'),
      );

    await tester.pumpWidget(
      _screenFor(_Source(rows: 0), widgetRegistry: registry),
    );
    await tester.pumpAndSettle();

    expect(find.text('host-owned empty state'), findsOneWidget);
    expect(find.text(const FilamentStrings().empty), findsNothing);
  });

  // Deliberately does NOT settle. The provider is still `initial` on the first
  // frame — load() runs in a post-frame callback — and a screen that treats
  // `initial` as anything but loading flashes "Nothing here yet" before the
  // records arrive. Every other test here settles first, so this is the only
  // one that can catch it. Sibling to the view screen's identical test.
  testWidgets('the first frame is a skeleton, never empty', (tester) async {
    await tester.pumpWidget(_screenFor(_Source()));

    expect(find.text(const FilamentStrings().empty), findsNothing);
    expect(find.byType(ResourceCard), findsWidgets);

    await tester.pumpAndSettle();
  });

  // The host owns the provider. A host that keeps one per resource — the
  // natural shape — would otherwise have its list blanked and refetched every
  // time the user came back from a record.
  testWidgets('a provider that already loaded is not reloaded on mount', (
    tester,
  ) async {
    usePhone(tester);
    final source = _Source();
    final provider = ResourceListProvider(source: source, resource: _resource);
    await provider.load();
    expect(source.listCalls, 1);

    await tester.pumpWidget(
      MaterialApp(home: ResourceListScreen(provider: provider)),
    );
    await tester.pumpAndSettle();

    expect(source.listCalls, 1);
    expect(find.byType(ResourceCard), findsNWidgets(2));
  });

  testWidgets(
    'schema polling refreshes a visible list and pauses for reorder',
    (tester) async {
      final source = _Source();
      final resource = ResourceSchema.fromJson(
        const {
          'key': 'banners',
          'labels': {'singular': 'Banner', 'plural': 'Banners'},
          'card': {
            'title': {'field': 'name'},
          },
          'reorder': {'column': 'position', 'direction': 'asc'},
        },
        'r',
        poll: const PollConfig(
          lists: Duration(seconds: 1),
          detail: Duration(seconds: 1),
          dashboard: Duration(seconds: 1),
        ),
      );
      final provider = ResourceListProvider(source: source, resource: resource);

      await tester.pumpWidget(
        MaterialApp(home: ResourceListScreen(provider: provider)),
      );
      await tester.pump();
      expect(source.listCalls, 1);

      await tester.pump(const Duration(milliseconds: 1200));
      expect(source.listCalls, 2);

      await provider.enterReorderMode();
      final afterReorderLoad = source.listCalls;
      await tester.pump(const Duration(milliseconds: 1200));
      expect(source.listCalls, afterReorderLoad);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('a resource channel refreshes on events with a slow watchdog', (
    tester,
  ) async {
    final source = _Source();
    final events = _EventTransport();
    final resource = ResourceSchema.fromJson(
      const {
        'key': 'banners',
        'labels': {'singular': 'Banner', 'plural': 'Banners'},
        'card': {
          'title': {'field': 'name'},
        },
        'channel': 'mobile.banners',
      },
      'r',
      poll: const PollConfig(
        lists: Duration(seconds: 1),
        detail: Duration(seconds: 1),
        dashboard: Duration(seconds: 1),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ResourceListScreen(
          provider: ResourceListProvider(source: source, resource: resource),
          eventTransport: events,
        ),
      ),
    );
    await tester.pump();
    expect(source.listCalls, 1);

    await tester.pump(const Duration(milliseconds: 1200));
    expect(source.listCalls, 1, reason: 'push replaces the ordinary cadence');

    events.controller.add(const RealtimeEvent.changed(resourceKey: 'banners'));
    await tester.pump();
    expect(source.listCalls, 2);

    await tester.pump(const Duration(seconds: 5));
    expect(source.listCalls, 3, reason: 'the 4x watchdog closes socket gaps');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(events.controller.close);
  });

  testWidgets('shows a card per record after loading', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(_screenFor(_Source()));
    await tester.pumpAndSettle();

    expect(find.byType(ResourceCard), findsNWidgets(2));
    expect(find.text('صف 0'), findsOneWidget);
  });

  testWidgets('shows a skeleton while loading, matching the card shape', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(_screenFor(_Source()));
    await tester.pump();

    expect(find.byType(ResourceCard), findsWidgets);

    await tester.pumpAndSettle();
  });

  testWidgets('shows empty when there are no records', (tester) async {
    await tester.pumpWidget(_screenFor(_Source(rows: 0)));
    await tester.pumpAndSettle();

    expect(find.byType(ResourceCard), findsNothing);
    expect(find.text(const FilamentStrings().empty), findsOneWidget);
  });

  testWidgets('shows a failure with a working retry', (tester) async {
    final source = _Source(error: Exception('تعذّر'));
    await tester.pumpWidget(_screenFor(source));
    await tester.pumpAndSettle();

    expect(find.text(const FilamentStrings().retry), findsOneWidget);

    await tester.tap(find.text(const FilamentStrings().retry));
    await tester.pumpAndSettle();

    expect(source.listCalls, 2);
  });

  testWidgets('a 401 reaches PanelUnauthenticated, not a generic failure', (
    tester,
  ) async {
    // Sibling to the same regression on PanelIndexScreen and
    // ResourceViewScreen — all three read providers expose
    // `isUnauthenticated`, but only the screens consuming it turn that
    // into the right widget.
    final source = _Source(
      error: const FilamentTransportException(
        'Unauthenticated.',
        statusCode: 401,
      ),
    );
    await tester.pumpWidget(_screenFor(source));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('panel.unauthenticated')), findsOneWidget);
  });

  testWidgets('debounces search rather than querying per keystroke', (
    tester,
  ) async {
    final source = _Source();
    await tester.pumpWidget(_screenFor(source));
    await tester.pumpAndSettle();

    final before = source.listCalls;

    await tester.enterText(find.byType(TextField), 'ا');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'ال');
    await tester.pump(const Duration(milliseconds: 100));

    expect(source.listCalls, before, reason: 'no query before the debounce');

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(source.listCalls, before + 1);
    expect(source.lastSearch, 'ال');
  });

  testWidgets('hides the search field when the resource is not searchable', (
    tester,
  ) async {
    final resource = ResourceSchema.fromJson(const {
      'key': 'banners',
      'labels': {'singular': 'a', 'plural': 'b'},
      'card': {
        'title': {'field': 'name'},
      },
    }, 'r');

    await tester.pumpWidget(
      MaterialApp(
        home: ResourceListScreen(
          provider: ResourceListProvider(source: _Source(), resource: resource),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('taps a card and reports the record', (tester) async {
    usePhone(tester);
    ResourceRecord? tapped;

    await tester.pumpWidget(
      _screenFor(_Source(), onRecordTap: (record) => tapped = record),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ResourceCard).first);
    await tester.pumpAndSettle();

    expect(tapped!.id, 0);
  });

  // The two tests below cover what a whole-branch mutation run found
  // uncovered: mutating this screen's scroll threshold (`* 0.8` → `* 1.5`)
  // and its `loadMoreFailed:` wiring (→ `false`) left all 538 tests green,
  // while the identical scroll mutation on the newer `RelationListScreen`
  // reds one. The older, more-used path had no pagination coverage at all.
  testWidgets('paginates when the list is scrolled near the bottom', (
    tester,
  ) async {
    // 20 rows so page 1 alone overflows the test viewport — a test dragging
    // a two-row list drags nothing and proves nothing.
    final source = _Source(rows: 20, pages: 2);

    await tester.pumpWidget(_screenFor(source));
    await tester.pumpAndSettle();

    expect(source.requestedPages, [1]);
    expect(find.text('صف 20'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(source.requestedPages, [1, 2]);
    expect(find.text('صف 20'), findsOneWidget);
  });

  testWidgets('fills a viewport page one leaves short by loading further pages '
      'unprompted', (tester) async {
    // Two rows per page cannot fill the test viewport, so the scroll
    // trigger has nothing to fire on: an infinite-scroll list whose first
    // page is short strands the user on it unless the screen fetches the
    // next page itself.
    final source = _Source(rows: 2, pages: 3);

    await tester.pumpWidget(_screenFor(source));
    await tester.pumpAndSettle();

    expect(source.requestedPages, [1, 2, 3]);
    // The last row of page 3: rows are numbered from 0, two per page.
    expect(find.text('صف 5'), findsOneWidget);
  });

  testWidgets('pull-to-refresh works on a list too short to scroll', (
    tester,
  ) async {
    final source = _Source(rows: 2, pages: 1);

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
    usePhone(tester);
    // The affordance `PaginatedCardList` added, asserted through THIS
    // screen — the widget's own test proves it renders when told to, not
    // that this screen tells it to.
    final source = _Source(rows: 20, pages: 2, failPage: 2);

    await tester.pumpWidget(_screenFor(source));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(source.requestedPages, [1, 2]);
    expect(find.byKey(const ValueKey('loadMore.failed')), findsOneWidget);
    // The server's own message, not a generic one — the failure used to set
    // an errorMessage nothing ever read.
    expect(find.textContaining('تعذّر تحميل الصفحة 2'), findsOneWidget);

    // Page one survives the failure: losing a scrolled list because page two
    // timed out is worse than the missing page.
    expect(find.byType(ResourceCard), findsWidgets);
  });

  testWidgets('renders in RTL without overflow', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ResourceListScreen(
            provider: ResourceListProvider(
              source: _Source(),
              resource: _resource,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ResourceCard), findsNWidgets(2));
  });

  group('adaptive layout (P23) — ListRowStyle', () {
    testWidgets('at 400 wide (compact) the list still uses cards', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_screenFor(_Source()));
      await tester.pumpAndSettle();

      expect(find.byType(ResourceCard), findsNWidgets(2));
      expect(find.byType(ResourceRow), findsNothing);
      expect(find.byType(ResourceRowHeader), findsNothing);
    });

    testWidgets('at 1200 wide (expanded) the list uses rows with a header', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_screenFor(_Source()));
      await tester.pumpAndSettle();

      expect(find.byType(ResourceRow), findsNWidgets(2));
      expect(find.byType(ResourceRowHeader), findsOneWidget);
      expect(find.byType(ResourceCard), findsNothing);
    });

    testWidgets('rowStyle: ListRowStyle.card forces cards even at 1200 wide', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _screenFor(_Source(), rowStyle: ListRowStyle.card),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ResourceCard), findsNWidgets(2));
      expect(find.byType(ResourceRow), findsNothing);
    });

    testWidgets('a row tap at 1200 wide still reports the record', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      ResourceRecord? tapped;
      await tester.pumpWidget(
        _screenFor(_Source(), onRecordTap: (record) => tapped = record),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ResourceRow).first);
      await tester.pumpAndSettle();

      expect(tapped!.id, 0);
    });
  });

  group('filters (P24)', () {
    testWidgets('renders no filter action when the resource publishes no '
        'filter nodes', (tester) async {
      await tester.pumpWidget(_screenFor(_Source()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.filter_list), findsNothing);
    });

    testWidgets(
      'shows a badge with the active filter count, seeded defaults included',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ResourceListScreen(
              provider: ResourceListProvider(
                source: _Source(),
                resource: _resourceWithFilters(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.filter_list), findsOneWidget);
        expect(
          find.descendant(of: find.byType(Badge), matching: find.text('2')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the chips row shows one chip per active filter and clears just the '
      'tapped one',
      (tester) async {
        final source = _Source();
        final provider = ResourceListProvider(
          source: source,
          resource: _resourceWithFilters(),
        );

        await tester.pumpWidget(
          MaterialApp(home: ResourceListScreen(provider: provider)),
        );
        await tester.pumpAndSettle();

        // Final wave, finding 8: the filter's own label leads, the way
        // Filament's own indicator reads ("Status: Draft"). With two
        // filters active, the option label alone is ambiguous — "Draft"
        // and "A" name nothing.
        expect(find.byType(InputChip), findsNWidgets(2));
        expect(find.text('Status: Draft'), findsOneWidget);
        expect(find.text('Category: A'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.widgetWithText(InputChip, 'Status: Draft'),
            matching: find.byIcon(Icons.close),
          ),
        );
        await tester.pumpAndSettle();

        expect(provider.filters['status'], '');
        expect(find.text('Status: Draft'), findsNothing);
        expect(find.byType(InputChip), findsNWidgets(1));
      },
    );

    testWidgets('opens as a bottom sheet at compact width (400)', (
      tester,
    ) async {
      usePhone(tester);
      final provider = ResourceListProvider(
        source: _Source(),
        resource: _resourceWithFilters(),
      );

      await tester.pumpWidget(
        MaterialApp(home: ResourceListScreen(provider: provider)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      expect(find.byType(FilterSheet), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('opens as a dialog at expanded width (1200)', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final provider = ResourceListProvider(
        source: _Source(),
        resource: _resourceWithFilters(),
      );

      await tester.pumpWidget(
        MaterialApp(home: ResourceListScreen(provider: provider)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      expect(find.byType(FilterSheet), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets(
      'a multiselect filter renders as one chip with its option labels '
      'joined, not the raw values',
      (tester) async {
        final provider = ResourceListProvider(
          source: _Source(),
          resource: _resourceWithMultiFilter(),
        );

        await tester.pumpWidget(
          MaterialApp(home: ResourceListScreen(provider: provider)),
        );
        await tester.pumpAndSettle();

        expect(find.byType(InputChip), findsOneWidget);
        expect(find.text('Tags: A, B'), findsOneWidget);
      },
    );

    // Review fix round 1, finding 1: unchecking every box used to leave an
    // empty `List` in `_filters` — a THIRD "cleared" shape `!= ''` guards
    // (the chip row, the badge) missed, rendering a blank chip and an
    // over-counted badge. `ResourceListProvider.setFilter` now
    // canonicalises `[]` to `''`, so this must render exactly like every
    // other cleared filter: no chip, no badge, and the request still
    // carries the bare `filter[tags]=`.
    testWidgets(
      'deselecting every box of a multiselect filter clears it — no chip, '
      'no badge, still filter[tags]= on the wire',
      (tester) async {
        usePhone(tester);
        final source = _Source();
        final provider = ResourceListProvider(
          source: source,
          resource: _resourceWithMultiFilter(),
        );

        await tester.pumpWidget(
          MaterialApp(home: ResourceListScreen(provider: provider)),
        );
        await tester.pumpAndSettle();

        expect(find.byType(InputChip), findsOneWidget);
        expect(
          find.descendant(of: find.byType(Badge), matching: find.text('1')),
          findsOneWidget,
        );

        await tester.tap(find.byIcon(Icons.filter_list));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(CheckboxListTile).at(0));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(CheckboxListTile).at(1));
        await tester.pumpAndSettle();

        expect(provider.filters, {'tags': ''});
        expect(provider.activeFilterCount, 0);
        expect(source.lastFilters, {'tags': ''});
        // The chip row lives on the screen behind the sheet, which is still
        // in the tree (a modal bottom sheet does not unmount what it
        // covers) and already rebuilt — the screen's own `ListenableBuilder`
        // is listening to the same `provider`.
        expect(find.byType(InputChip), findsNothing);
        expect(
          find.descendant(of: find.byType(Badge), matching: find.text('1')),
          findsNothing,
        );
      },
    );
  });
}

/// One multiselect filter, defaulted to both its options — the chip-label
/// `List` branch [_resourceWithFilters]'s single-value filters never touch.
ResourceSchema _resourceWithMultiFilter() => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'لافتة', 'plural': 'اللافتات'},
  'recordKey': 'id',
  'card': {
    'title': {'field': 'name'},
  },
  'filters': [
    {
      'type': 'select',
      'name': 'tags',
      'label': 'Tags',
      'config': {
        'options': [
          {'value': 'a', 'label': 'A'},
          {'value': 'b', 'label': 'B'},
        ],
        'multiple': true,
      },
      'default': ['a', 'b'],
    },
  ],
}, 'r');

/// Two defaulted filters (P24) — `activeFilterCount` reads `2` from the
/// first frame per `ResourceListProvider.activeFilterCount`'s own doc, which
/// is what the badge and chip-row tests above both lean on.
ResourceSchema _resourceWithFilters() => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'لافتة', 'plural': 'اللافتات'},
  'recordKey': 'id',
  'card': {
    'title': {'field': 'name'},
  },
  'filters': [
    {
      'type': 'select',
      'name': 'status',
      'label': 'Status',
      'config': {
        'options': [
          {'value': 'draft', 'label': 'Draft'},
          {'value': 'published', 'label': 'Published'},
        ],
      },
      'default': 'draft',
    },
    {
      'type': 'select',
      'name': 'category',
      'label': 'Category',
      'config': {
        'options': [
          {'value': 'a', 'label': 'A'},
          {'value': 'b', 'label': 'B'},
        ],
      },
      'default': 'a',
    },
  ],
}, 'r');
