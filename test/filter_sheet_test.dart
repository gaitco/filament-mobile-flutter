// Task 5 of P24: the filter sheet's own content — the resource's published
// filter nodes (`resource.filters`), each rendered through the package's own
// `SelectFieldWidget` against `ResourceListProvider`'s live filter state.
//
// Deliberately tested as a plain content widget, not through
// `ResourceListScreen`'s app-bar action — the sheet/dialog choice and the
// RTL wrap are that screen's job, covered in `resource_list_screen_test.dart`
// and `rtl_layout_test.dart` instead.

import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/form/fields/field_widgets.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/resource_list_provider.dart';
import 'package:filament_mobile/ui/filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers `list()` with zero records and throws on everything else — the
/// sheet never reads records, only `ResourceListProvider.setFilter`/
/// `clearFilters`' own refetch, which just needs somewhere to land.
class _Source implements ResourceDataSource {
  Map<String, Object?> lastFilters = const {};

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
    lastFilters = filters;
    return const PaginatedRecords(
      records: [],
      meta: PageMeta(currentPage: 1, lastPage: 1, perPage: 20, total: 0),
    );
  }

  @override
  Future<void> reorder(String resourceKey, List<Object> ids) =>
      throw UnimplementedError();

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

class _RemoteSource extends _Source implements FilterOptionsDataSource {
  String? searchedFilter;
  String? searchedQuery;

  @override
  Future<OptionsPage> filterOptions(
    String resourceKey, {
    required String filter,
    required String query,
  }) async {
    searchedFilter = filter;
    searchedQuery = query;
    return const OptionsPage(
      options: [SelectOption(value: 'archived', label: 'Archived')],
      hasMore: false,
    );
  }
}

/// Two single-value filters, no defaults — the plain case Task 3's provider
/// tests already cover the seeding for, so nothing here starts "active".
ResourceSchema _resourceWithTwoFilters() => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'Banner', 'plural': 'Banners'},
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
    },
  ],
}, 'r');

/// One ternary filter — labelled distinctly from either of its own two
/// options, so `find.text('Active')` after opening the menu can only match
/// the option, not the field's own label.
ResourceSchema _resourceWithTernary() => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'Banner', 'plural': 'Banners'},
  'filters': [
    {
      'type': 'select',
      'name': 'active',
      'label': 'Status filter',
      'config': {
        'options': [
          {'value': '1', 'label': 'Active'},
          {'value': '0', 'label': 'Inactive'},
        ],
      },
    },
  ],
}, 'r');

/// Same shape as [_resourceWithTernary], but with a seeded `default` — the
/// case "Any" actually exists for (`ResourceListProvider._seedFilters`'s own
/// doc): a filter with no default is already unfiltered, so clearing it is
/// a no-op the wire can't even distinguish from never having touched it.
ResourceSchema _resourceWithDefaultedTernary() =>
    ResourceSchema.fromJson(const {
      'key': 'banners',
      'labels': {'singular': 'Banner', 'plural': 'Banners'},
      'filters': [
        {
          'type': 'select',
          'name': 'active',
          'label': 'Status filter',
          'config': {
            'options': [
              {'value': '1', 'label': 'Active'},
              {'value': '0', 'label': 'Inactive'},
            ],
          },
          'default': '1',
        },
      ],
    }, 'r');

/// A `TrashedFilter`-shaped node: the blank branch is `withoutTrashed()`,
/// which is what `config.placeholder` names — see the test that uses this.
ResourceSchema _resourceWithPlaceholder() => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'Banner', 'plural': 'Banners'},
  'filters': [
    {
      'type': 'select',
      'name': 'trashed',
      'label': 'Trashed',
      'config': {
        'options': [
          {'value': '1', 'label': 'With trashed'},
          {'value': '0', 'label': 'Only trashed'},
        ],
        'placeholder': 'Without trashed',
      },
    },
  ],
}, 'r');

/// A panel that keyed one of its filter options `''` — server-side that
/// option can never narrow anything (Filament reads a blank select value as
/// "any"), but on the wire it is a perfectly ordinary option.
ResourceSchema _resourceWithEmptyValuedOption() =>
    ResourceSchema.fromJson(const {
      'key': 'banners',
      'labels': {'singular': 'Banner', 'plural': 'Banners'},
      'filters': [
        {
          'type': 'select',
          'name': 'status',
          'label': 'Status',
          'config': {
            'options': [
              {'value': '', 'label': 'Unset'},
              {'value': 'real', 'label': 'Real'},
            ],
          },
        },
      ],
    }, 'r');

Future<void> _pumpSheet(WidgetTester tester, ResourceListProvider provider) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FilterSheet(provider: provider)),
      ),
    );

void main() {
  testWidgets('renders every filter node through SelectFieldWidget', (
    tester,
  ) async {
    final provider = ResourceListProvider(
      source: _Source(),
      resource: _resourceWithTwoFilters(),
    );

    await _pumpSheet(tester, provider);
    await tester.pumpAndSettle();

    expect(find.byType(SelectFieldWidget), findsNWidgets(2));
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
  });

  testWidgets('picking an option calls setFilter with the option\'s value', (
    tester,
  ) async {
    final provider = ResourceListProvider(
      source: _Source(),
      resource: _resourceWithTwoFilters(),
    );

    await _pumpSheet(tester, provider);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<Object?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draft').last);
    await tester.pumpAndSettle();

    expect(provider.filters['status'], 'draft');
  });

  testWidgets('Clear all calls clearFilters and closes', (tester) async {
    final provider = ResourceListProvider(
      source: _Source(),
      resource: _resourceWithTwoFilters(),
    );
    await provider.setFilter('status', 'draft');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      Dialog(child: FilterSheet(provider: provider)),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(FilterSheet), findsOneWidget);

    await tester.tap(find.text(const FilamentStrings().clearFilters));
    await tester.pumpAndSettle();

    expect(find.byType(FilterSheet), findsNothing);
    expect(provider.filters, {'status': '', 'category': ''});
  });

  testWidgets(
    'a ternary node with no placeholder shows three choices, the blank one '
    'labelled anyOption',
    (tester) async {
      final provider = ResourceListProvider(
        source: _Source(),
        resource: _resourceWithTernary(),
      );

      await _pumpSheet(tester, provider);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<Object?>));
      await tester.pumpAndSettle();

      // Review fix round 1, finding 3: a never-touched filter now reads as
      // the same `''` a cleared one does, so "Any" is already the closed
      // field's own selection AND one of the open menu's three items —
      // `findsWidgets`, not `findsOneWidget`, is the correct shape here, not
      // a regression.
      expect(find.text(const FilamentStrings().anyOption), findsWidgets);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
    },
  );

  // Final wave, finding 2. The blank row is NOT always "no filter": a
  // `TrashedFilter`'s blank branch is `withoutTrashed()` (vendor
  // `TrashedFilter.php:27-31`), so labelling it "Any" tells the user the
  // filter was removed when it was not. The server publishes the filter's
  // own `config.placeholder` for exactly this; the sheet must use it.
  testWidgets(
    'a node with config.placeholder labels its blank row with it, not '
    'anyOption',
    (tester) async {
      final provider = ResourceListProvider(
        source: _Source(),
        resource: _resourceWithPlaceholder(),
      );

      await _pumpSheet(tester, provider);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<Object?>));
      await tester.pumpAndSettle();

      expect(find.text('Without trashed'), findsWidgets);
      expect(find.text(const FilamentStrings().anyOption), findsNothing);
      expect(find.text('With trashed'), findsOneWidget);
    },
  );

  // Final wave, finding 9. `PublishedFilter` will happily emit an option
  // keyed `''`, which collides with the sheet's own "Any" sentinel — two
  // dropdown entries sharing one value trips Flutter's "exactly one item"
  // assertion, taking the whole sheet down.
  testWidgets('an option whose value is empty does not collide with "Any"', (
    tester,
  ) async {
    final provider = ResourceListProvider(
      source: _Source(),
      resource: _resourceWithEmptyValuedOption(),
    );

    await _pumpSheet(tester, provider);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<Object?>));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(const FilamentStrings().anyOption), findsWidgets);
    expect(find.text('Real'), findsOneWidget);
  });

  // Review fix round 1, finding 2: the test above only proves "Any" is
  // OFFERED, never that picking it reaches `setFilter(name, null)` — the
  // one call that makes the client send an explicit `filter[name]=` rather
  // than omitting the key. Get this wrong and a defaulted filter's "Any"
  // silently does nothing: the server reinstates the default on the very
  // next request, exactly the bug Task 4 fixed one layer down.
  testWidgets(
    'tapping "Any" on a defaulted filter explicitly clears it, not just '
    'omits its value',
    (tester) async {
      final source = _Source();
      final provider = ResourceListProvider(
        source: source,
        resource: _resourceWithDefaultedTernary(),
      );
      // The seeded default, sent before any interaction — see
      // `ResourceListProvider._seedFilters`'s doc.
      expect(provider.filters, {'active': '1'});

      await _pumpSheet(tester, provider);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<Object?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(const FilamentStrings().anyOption));
      await tester.pumpAndSettle();

      expect(
        provider.filters,
        {'active': ''},
        reason:
            'an explicit empty string, never a removed key — an omitted '
            'key reads server-side as "apply this filter\'s default"',
      );
      expect(provider.activeFilterCount, 0);
      expect(source.lastFilters, {'active': ''});
    },
  );

  testWidgets('a cleared multiselect filter re-renders without crashing', (
    tester,
  ) async {
    // `ResourceListProvider._filters` stores an explicitly cleared filter
    // as `''` regardless of the filter's own shape — including a
    // multiselect one, whose own `SelectFieldWidget._multi` casts its
    // value straight to `List<Object?>?`. A bare `''` there throws unless
    // `FilterSheet._field` translates it to `null` first.
    final provider = ResourceListProvider(
      source: _Source(),
      resource: _resourceWithMultiFilter(),
    );
    await provider.clearFilters();
    expect(provider.filters['tags'], '');

    await _pumpSheet(tester, provider);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
  });

  testWidgets('a remote filter searches by its filter name and applies', (
    tester,
  ) async {
    final source = _RemoteSource();
    final provider = ResourceListProvider(
      source: source,
      resource: _resourceWithRemoteFilter(),
    );

    await _pumpSheet(tester, provider);
    await tester.tap(
      find.descendant(
        of: find.byType(RemoteSelectField),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();

    expect(source.searchedFilter, 'status');
    expect(source.searchedQuery, '');
    expect(find.text(const FilamentStrings().anyOption), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(provider.filters['status'], 'archived');
    expect(source.lastFilters, {'status': 'archived'});
  });
}

/// One multiselect filter, defaulted to both its options — exercises the
/// `List<Object?>` value branch [_resourceWithTwoFilters]'s single-value
/// filters never touch.
ResourceSchema _resourceWithMultiFilter() => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'Banner', 'plural': 'Banners'},
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

ResourceSchema _resourceWithRemoteFilter() => ResourceSchema.fromJson(const {
  'key': 'banners',
  'labels': {'singular': 'Banner', 'plural': 'Banners'},
  'filters': [
    {
      'type': 'select',
      'name': 'status',
      'label': 'Status',
      'config': {
        'optionsUrl': '/api/mobile-panel/banners/filter-options',
        'searchable': true,
      },
    },
  ],
}, 'r');
