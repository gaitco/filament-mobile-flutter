import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/resource_list_provider.dart';
import 'package:filament_mobile/ui/resource_card.dart';
import 'package:filament_mobile/ui/resource_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source implements ResourceDataSource {
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
  final List<int> requestedPages = [];

  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
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
  }) async {
    listCalls++;
    lastSearch = search;
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

Widget screenFor(_Source source, {void Function(ResourceRecord)? onRecordTap}) {
  return MaterialApp(
    home: ResourceListScreen(
      provider: ResourceListProvider(source: source, resource: _resource),
      onRecordTap: onRecordTap,
    ),
  );
}

void main() {
  // Deliberately does NOT settle. The provider is still `initial` on the first
  // frame — load() runs in a post-frame callback — and a screen that treats
  // `initial` as anything but loading flashes "Nothing here yet" before the
  // records arrive. Every other test here settles first, so this is the only
  // one that can catch it. Sibling to the view screen's identical test.
  testWidgets('the first frame is a skeleton, never empty', (tester) async {
    await tester.pumpWidget(screenFor(_Source()));

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

  testWidgets('shows a card per record after loading', (tester) async {
    await tester.pumpWidget(screenFor(_Source()));
    await tester.pumpAndSettle();

    expect(find.byType(ResourceCard), findsNWidgets(2));
    expect(find.text('صف 0'), findsOneWidget);
  });

  testWidgets('shows a skeleton while loading, matching the card shape', (
    tester,
  ) async {
    await tester.pumpWidget(screenFor(_Source()));
    await tester.pump();

    expect(find.byType(ResourceCard), findsWidgets);

    await tester.pumpAndSettle();
  });

  testWidgets('shows empty when there are no records', (tester) async {
    await tester.pumpWidget(screenFor(_Source(rows: 0)));
    await tester.pumpAndSettle();

    expect(find.byType(ResourceCard), findsNothing);
    expect(find.text(const FilamentStrings().empty), findsOneWidget);
  });

  testWidgets('shows a failure with a working retry', (tester) async {
    final source = _Source(error: Exception('تعذّر'));
    await tester.pumpWidget(screenFor(source));
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
    await tester.pumpWidget(screenFor(source));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('panel.unauthenticated')), findsOneWidget);
  });

  testWidgets('debounces search rather than querying per keystroke', (
    tester,
  ) async {
    final source = _Source();
    await tester.pumpWidget(screenFor(source));
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
    ResourceRecord? tapped;

    await tester.pumpWidget(
      screenFor(_Source(), onRecordTap: (record) => tapped = record),
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

    await tester.pumpWidget(screenFor(source));
    await tester.pumpAndSettle();

    expect(source.requestedPages, [1]);
    expect(find.text('صف 20'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(source.requestedPages, [1, 2]);
    expect(find.text('صف 20'), findsOneWidget);
  });

  testWidgets('offers a retry when the next page fails, keeping page one', (
    tester,
  ) async {
    // The affordance `PaginatedCardList` added, asserted through THIS
    // screen — the widget's own test proves it renders when told to, not
    // that this screen tells it to.
    final source = _Source(rows: 20, pages: 2, failPage: 2);

    await tester.pumpWidget(screenFor(source));
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
}
