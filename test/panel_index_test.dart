import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
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
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
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
}

Widget indexHarness({
  List<String> resources = const [],
  Map<String, String> groups = const {},
  void Function(ResourceSchema)? onResourceTap,
  Object? error,
}) {
  return MaterialApp(
    home: PanelIndexScreen(
      provider: PanelProvider(
        _Source(resources: resources, groups: groups, error: error),
      ),
      onResourceTap: onResourceTap ?? (_) {},
    ),
  );
}

void main() {
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
