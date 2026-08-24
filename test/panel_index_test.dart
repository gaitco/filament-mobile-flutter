import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/panel_provider.dart';
import 'package:filament_mobile/ui/panel_index_screen.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_until_found.dart';

class _Source implements ResourceDataSource {
  @override
  Future<void> reorder(String resourceKey, List<Object> ids) =>
      throw UnimplementedError();
  _Source({this.resources = const [], this.groups = const {}, this.error});

  final List<String> resources;
  final Map<String, String> groups;
  final Object? error;

  @override
  Future<PanelSchema> panel() async {
    if (error != null) throw error!;

    return PanelSchema.fromJson({
      'version': 1,
      'panel': {'id': 'mobile', 'title': 'Panel'},
      'resources': [
        for (final key in resources)
          {
            'key': key,
            'labels': {'singular': key, 'plural': key},
            if (groups[key] != null) 'group': groups[key],
          },
      ],
    });
  }

  @override
  Future<PanelSchema?> cachedPanel() async => null;

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
  }) async => throw UnimplementedError();

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

Widget indexHarness({
  List<String> resources = const [],
  Map<String, String> groups = const {},
  void Function(ResourceSchema)? onResourceTap,
  Widget? Function(ResourceSchema)? leading,
  Object? error,
  TextDirection direction = TextDirection.ltr,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: PanelIndexScreen(
        provider: PanelProvider(
          _Source(resources: resources, groups: groups, error: error),
        ),
        onResourceTap: onResourceTap ?? (_) {},
        leading: leading,
      ),
    ),
  );
}

void main() {
  testWidgets('the row chevron points the way the panel reads', (tester) async {
    // The GLYPH, not just its slot. `ListTile` already moves `trailing` to the
    // leading edge under RTL, so a right-pointing chevron there points back at
    // the text it is meant to lead away from.
    await tester.pumpWidget(indexHarness(resources: const ['orders']));
    await pumpUntilFound(tester, find.byType(ListTile));

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
  });

  testWidgets('the row chevron flips under RTL', (tester) async {
    await tester.pumpWidget(
      indexHarness(resources: const ['orders'], direction: TextDirection.rtl),
    );
    await pumpUntilFound(tester, find.byType(ListTile));

    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('the AppBar title renders once the panel loads', (tester) async {
    // The whole Scaffold must sit inside the ListenableBuilder — a
    // body-only builder rebuilds the list but never the AppBar, so the
    // title (only known after `load()` resolves) stays empty forever.
    await tester.pumpWidget(indexHarness(resources: ['banners']));
    await pumpUntilFound(tester, find.text('Panel'));

    expect(find.text('Panel'), findsOneWidget);
  });

  testWidgets('lists every resource the user may see', (tester) async {
    await tester.pumpWidget(indexHarness(resources: ['banners', 'posts']));
    await pumpUntilFound(tester, find.byType(ListTile));

    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('a leading builder renders per resource, null renders none', (
    tester,
  ) async {
    // The contract carries no icon, so the mapping is the host's — and a
    // resource the host has no icon for must render exactly as it did
    // before the parameter existed, not with an empty leading slot.
    await tester.pumpWidget(
      indexHarness(
        resources: ['banners', 'posts'],
        leading: (resource) =>
            resource.key == 'banners' ? const Icon(Icons.flag) : null,
      ),
    );
    await pumpUntilFound(tester, find.byType(ListTile));

    expect(find.byIcon(Icons.flag), findsOneWidget);
    final postsTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('posts'), matching: find.byType(ListTile)),
    );
    expect(postsTile.leading, isNull);
  });

  testWidgets('an empty panel is an explicit state, never a spinner', (
    tester,
  ) async {
    // THE regression. The load SUCCEEDED and the answer is "nothing" — a
    // spinner says "still working", which is what shipped and span forever.
    await tester.pumpWidget(indexHarness(resources: []));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('panel.empty')), findsOneWidget);
  });

  testWidgets('groups render as headings, ungrouped first', (tester) async {
    await tester.pumpWidget(
      indexHarness(
        resources: ['banners', 'posts'],
        groups: {'banners': 'Content'},
      ),
    );
    await pumpUntilFound(tester, find.byType(ListTile));

    final headings = find.byKey(const ValueKey('panel.group.Content'));
    expect(headings, findsOneWidget);

    // `posts` is ungrouped and must sort above the group heading, matching
    // Filament's own panel.
    final postsY = tester.getTopLeft(find.text('posts')).dy;
    expect(postsY, lessThan(tester.getTopLeft(headings).dy));
  });

  testWidgets('tapping a resource reports it', (tester) async {
    ResourceSchema? tapped;
    await tester.pumpWidget(
      indexHarness(resources: ['banners'], onResourceTap: (r) => tapped = r),
    );
    await pumpUntilFound(tester, find.byType(ListTile));

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(tapped?.key, 'banners');
  });

  testWidgets('a failure renders through the host builder, not a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(indexHarness(error: 'boom'));
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);
  });

  testWidgets('a 401 reaches PanelUnauthenticated, not a generic failure', (
    tester,
  ) async {
    // The carried finding from Task 5's review: nothing consumed
    // `provider.isUnauthenticated` yet, so a 401 rendered as PanelFailure
    // — the same "server is broken" message as any other error, on the
    // one case that means "you were signed out".
    await tester.pumpWidget(
      indexHarness(
        error: const FilamentTransportException(
          'Unauthenticated.',
          statusCode: 401,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('panel.unauthenticated')), findsOneWidget);
  });
}
