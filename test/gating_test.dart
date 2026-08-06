import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/resource_list_provider.dart';
import 'package:filament_mobile/state/resource_view_provider.dart';
import 'package:filament_mobile/ui/resource_list_screen.dart';
import 'package:filament_mobile/ui/resource_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_until_found.dart';

/// A data source that never needs more than one row or one record — this
/// suite only cares about which affordances render, not what the data looks
/// like.
class _Source implements ResourceDataSource {
  _Source({this.recordPermissions = const {}});

  final Map<String, dynamic> recordPermissions;

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async => PaginatedRecords(
    records: [
      ResourceRecord.fromJson(const {'id': 1, 'name': 'صف'}, 'id'),
    ],
    meta: const PageMeta(currentPage: 1, lastPage: 1, perPage: 20, total: 1),
  );

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async =>
      ResourceRecord.fromJson(
        const {'id': 1, 'name': 'صف'},
        'id',
        permissions: recordPermissions,
      );

  @override
  Future<PanelSchema> panel() async => throw UnimplementedError();

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

/// [permissions] is the resource-level block ("this resource supports
/// create/update"). Record-level authorization is a separate map entirely —
/// see [_Source.recordPermissions] — because P1 drew that line and P3a made
/// crossing it a compile error.
ResourceSchema _resourceWith(Map<String, bool> permissions) =>
    ResourceSchema.fromJson({
      'key': 'users',
      'labels': {'singular': 'مستخدم', 'plural': 'المستخدمون'},
      'recordKey': 'id',
      'permissions': permissions,
      'card': {
        'title': {'field': 'name'},
      },
      'infolist': [
        {'type': 'text_entry', 'name': 'name', 'label': 'الاسم'},
      ],
    }, 'r');

Widget listHarness({Map<String, bool> permissions = const {}}) {
  return MaterialApp(
    home: ResourceListScreen(
      provider: ResourceListProvider(
        source: _Source(),
        resource: _resourceWith(permissions),
      ),
    ),
  );
}

Widget viewHarness({
  Map<String, bool> resourcePermissions = const {},
  Map<String, bool> recordPermissions = const {},
}) {
  return MaterialApp(
    home: ResourceViewScreen(
      provider: ResourceViewProvider(
        source: _Source(recordPermissions: recordPermissions),
        resource: _resourceWith(resourcePermissions),
        id: 1,
      ),
    ),
  );
}

void main() {
  testWidgets('no create button when the resource forbids create', (
    tester,
  ) async {
    await tester.pumpWidget(listHarness(permissions: {'create': false}));
    await pumpUntilFound(tester, find.byType(ListView));

    expect(find.byKey(const ValueKey('resource.create')), findsNothing);
  });

  testWidgets('a create button when the resource permits it', (tester) async {
    // The counter-test: gating that hides everything would pass the test above.
    await tester.pumpWidget(listHarness(permissions: {'create': true}));
    await pumpUntilFound(tester, find.byType(ListView));

    expect(find.byKey(const ValueKey('resource.create')), findsOneWidget);
  });

  testWidgets('no edit affordance when the RECORD forbids update', (
    tester,
  ) async {
    // The two-block distinction, and only a record-level test can catch it:
    // the resource-level key says yes while this row says no.
    await tester.pumpWidget(
      viewHarness(
        resourcePermissions: {'update': true},
        recordPermissions: {'update': false},
      ),
    );
    await pumpUntilFound(tester, find.text('صف'));

    expect(find.byKey(const ValueKey('record.edit')), findsNothing);
  });

  testWidgets('an edit affordance when the record permits it', (tester) async {
    await tester.pumpWidget(
      viewHarness(
        resourcePermissions: {'update': true},
        recordPermissions: {'update': true},
      ),
    );
    await pumpUntilFound(tester, find.byKey(const ValueKey('record.edit')));

    expect(find.byKey(const ValueKey('record.edit')), findsOneWidget);
  });
}
