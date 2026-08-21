import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:filament_mobile/state/resource_view_provider.dart';
import 'package:filament_mobile/ui/relation_section_widget.dart';
import 'package:filament_mobile/ui/resource_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/expect_width_capped.dart';
import 'support/pump_until_found.dart';

/// The resource-level block says delete is permitted — capability. The record
/// block disagrees when a test sets it to false, which is the whole point of
/// the distinction: [recordPermissions] here and `resourcePermissions` in
/// [viewHarness] vary independently.
class FakeSource implements ResourceDataSource {
  @override
  Future<void> reorder(String resourceKey, List<Object> ids) =>
      throw UnimplementedError();
  FakeSource({
    this.error,
    this.recordPermissions = const {},
    this.deleteResult = const WriteSuccess({}),
    this.recordActions = const [],
    this.actionResult = const ActionSuccess(null),
    this.relationResult,
    this.relationError,
  });

  final Object? error;
  final Map<String, dynamic> recordPermissions;
  final WriteResult deleteResult;

  /// What `relation()` resolves to. Null (the default, like every other
  /// method here a test doesn't touch) makes it throw — a test that never
  /// queues a relation response never expects one fetched.
  final PaginatedRecords? relationResult;
  final Object? relationError;

  final List<({String resourceKey, Object id, String relationKey, int page})>
  relationCalls = [];

  /// Raw action entries, parsed the same way the server payload is —
  /// `ResourceRecord.fromJson`'s own `actions` param, not a `RecordAction`
  /// list, so a test exercises the same parsing the real record does.
  final List<dynamic> recordActions;
  ActionResult actionResult;

  int recordCalls = 0;
  int deleteCalls = 0;
  final List<String> ranActions = [];

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async {
    recordCalls++;
    if (error != null) throw error!;

    return ResourceRecord.fromJson(
      const {'id': 1, 'name': 'أحمد', 'is_active': true},
      'id',
      permissions: recordPermissions,
      actions: recordActions,
    );
  }

  @override
  Future<WriteResult> destroy(String resourceKey, Object id) async {
    deleteCalls++;
    return deleteResult;
  }

  @override
  Future<ActionResult> runAction(
    String resourceKey,
    Object id,
    String action,
  ) async {
    ranActions.add(action);
    return actionResult;
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
    bool reorder = false,
  }) async => throw UnimplementedError();

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
    relationCalls.add((
      resourceKey: resourceKey,
      id: id,
      relationKey: relation.key,
      page: page,
    ));
    if (relationError != null) throw relationError!;
    if (relationResult == null) throw UnimplementedError();
    return relationResult!;
  }

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

/// [permissions] is the **resource**-level block ("this resource supports
/// deletion"). The record's own block is set separately, via
/// [FakeSource.recordPermissions] — the two are never the same map.
/// [relations] is the raw wire shape (`RelationDescriptor.fromJson` parses
/// it), empty by default like every other resource in this file.
ResourceSchema _resourceWith(
  Map<String, bool> permissions, {
  List<Map<String, dynamic>> relations = const [],
}) => ResourceSchema.fromJson({
  'key': 'users',
  'labels': {'singular': 'مستخدم', 'plural': 'المستخدمون'},
  'recordKey': 'id',
  'permissions': permissions,
  'relations': relations,
  'infolist': [
    {'type': 'text_entry', 'name': 'name', 'label': 'الاسم'},
    {'type': 'boolean_entry', 'name': 'is_active', 'label': 'نشط'},
  ],
}, 'r');

Widget viewHarness({
  FakeSource? source,
  Map<String, bool> resourcePermissions = const {'delete': true},
  Map<String, bool>? recordPermissions,
  List<Map<String, dynamic>> relations = const [],
}) {
  final resolvedSource =
      source ?? FakeSource(recordPermissions: recordPermissions ?? const {});

  return MaterialApp(
    home: ResourceViewScreen(
      provider: ResourceViewProvider(
        source: resolvedSource,
        resource: _resourceWith(resourcePermissions, relations: relations),
        id: 1,
      ),
    ),
  );
}

/// Server-published actions live behind the record screen's overflow menu, so
/// every test that reaches one opens it first. Kept as a helper rather than
/// repeated inline: the indirection is the *point* of the menu, and a test
/// that forgets the step fails with "Approve not found", which reads as the
/// action being missing rather than as the menu being shut.
Future<void> _openActions(WidgetTester tester) async {
  await pumpUntilFound(
    tester,
    find.byKey(const ValueKey('record.actions.menu')),
  );
  await tester.tap(find.byKey(const ValueKey('record.actions.menu')));
  await tester.pumpAndSettle();
}

void main() {
  group('ResourceViewProvider', () {
    test('load() moves through loading to success', () async {
      final provider = ResourceViewProvider(
        source: FakeSource(),
        resource: _resourceWith(const {'delete': true}),
        id: 1,
      );
      final seen = <LoadStatus>[];
      provider.addListener(() => seen.add(provider.status));

      await provider.load();

      expect(seen, [LoadStatus.loading, LoadStatus.success]);
      expect(provider.record!.get<String>('name'), 'أحمد');
    });

    test('a failure sets a message', () async {
      final provider = ResourceViewProvider(
        source: FakeSource(error: Exception('تعذّر')),
        resource: _resourceWith(const {'delete': true}),
        id: 1,
      );

      await provider.load();

      expect(provider.status, LoadStatus.failure);
      expect(provider.errorMessage, contains('تعذّر'));
    });

    test('delete() passes straight through to the data source', () async {
      final source = FakeSource(deleteResult: const WriteGone('gone'));
      final provider = ResourceViewProvider(
        source: source,
        resource: _resourceWith(const {'delete': true}),
        id: 1,
      );

      final result = await provider.delete();

      expect(source.deleteCalls, 1);
      expect(result, isA<WriteGone>());
    });
  });

  group('ResourceViewScreen', () {
    // Deliberately does NOT settle. The provider is still `initial` on the
    // first frame — load() runs in a post-frame callback — and a screen that
    // treats `initial` as anything but loading flashes "Nothing here yet"
    // before the record arrives. Every other test here settles first, so this
    // is the only one that can catch it.
    testWidgets('the first frame is loading, never empty', (tester) async {
      await tester.pumpWidget(viewHarness());

      expect(find.text('Nothing here yet'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
    });

    // The host owns the provider, so a re-mount must not throw away a record
    // it already has.
    testWidgets('a provider that already loaded is not reloaded on mount', (
      tester,
    ) async {
      final source = FakeSource();
      final provider = ResourceViewProvider(
        source: source,
        resource: _resourceWith(const {'delete': true}),
        id: 1,
      );
      await provider.load();

      await tester.pumpWidget(
        MaterialApp(home: ResourceViewScreen(provider: provider)),
      );
      await tester.pumpAndSettle();

      expect(source.recordCalls, 1);
      expect(find.text('أحمد'), findsOneWidget);
    });

    testWidgets('renders the infolist entries', (tester) async {
      await tester.pumpWidget(viewHarness());
      await tester.pumpAndSettle();

      expect(find.text('الاسم'), findsOneWidget);
      expect(find.text('أحمد'), findsOneWidget);
      expect(find.text('نشط'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('shows a failure with a working retry', (tester) async {
      final source = FakeSource(error: Exception('boom'));
      await tester.pumpWidget(viewHarness(source: source));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(source.recordCalls, 2);
    });

    testWidgets('a 401 reaches PanelUnauthenticated, not a generic failure', (
      tester,
    ) async {
      // Sibling to the same regression on PanelIndexScreen and
      // ResourceListScreen.
      final source = FakeSource(
        error: const FilamentTransportException(
          'Unauthenticated.',
          statusCode: 401,
        ),
      );
      await tester.pumpWidget(viewHarness(source: source));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('panel.unauthenticated')),
        findsOneWidget,
      );
    });

    testWidgets('the affordance is absent when the RECORD denies delete', (
      tester,
    ) async {
      // The resource-level key says "this resource supports deletion"; the
      // record-level one says "you may delete THIS row". Under an ownership
      // policy they disagree for most rows.
      await tester.pumpWidget(
        viewHarness(
          resourcePermissions: const {'delete': true},
          recordPermissions: const {'delete': false},
        ),
      );
      await pumpUntilFound(tester, find.text('أحمد'));

      expect(find.byKey(const ValueKey('record.delete')), findsNothing);
    });

    testWidgets('shows the affordance when the record permits it', (
      tester,
    ) async {
      await tester.pumpWidget(
        viewHarness(recordPermissions: const {'delete': true}),
      );
      await pumpUntilFound(tester, find.byKey(const ValueKey('record.delete')));

      expect(find.byKey(const ValueKey('record.delete')), findsOneWidget);
    });

    testWidgets(
      'the affordance is absent when the record carries no permissions at all',
      (tester) async {
        // The list endpoint never computes per-record permissions, so a
        // record read from it arrives with an empty map — the same code path
        // as an explicit `false` (`permissions[ability] ?? false`), but this
        // pins it through the screen rather than only through Task 5's
        // isolated `recordCan` suite: if the default ever flipped, this is
        // the test that would put a delete button on every row.
        await tester.pumpWidget(viewHarness(recordPermissions: const {}));
        await pumpUntilFound(tester, find.text('أحمد'));

        expect(find.byKey(const ValueKey('record.delete')), findsNothing);
      },
    );

    testWidgets(
      'the delete affordance carries an accessible label, not just an icon',
      (tester) async {
        // An icon-only IconButton with no tooltip gives the control no
        // accessible name, so a screen reader announces an unlabelled
        // "button" on a destructive control. `find.byTooltip` reads the
        // semantics tree's `tooltip` field — the one IconButton actually
        // populates from its `tooltip:` argument — so this fails on a bare
        // `Icon` with no tooltip wired, where `find.byKey` alone would not.
        // (`bySemanticsLabel` checks a different field, `label`, and never
        // sees IconButton's tooltip at all.)
        // Disposed inline rather than via `addTearDown`: Flutter's own
        // "no SemanticsHandle left active" check runs before `addTearDown`
        // callbacks fire, so a handle only released that way still reads as
        // leaked.
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          viewHarness(recordPermissions: const {'delete': true}),
        );
        await pumpUntilFound(
          tester,
          find.byKey(const ValueKey('record.delete')),
        );

        expect(find.byTooltip('Delete'), findsOneWidget);

        handle.dispose();
      },
    );

    testWidgets('delete asks first', (tester) async {
      final source = FakeSource(recordPermissions: const {'delete': true});
      await tester.pumpWidget(viewHarness(source: source));
      await pumpUntilFound(tester, find.byKey(const ValueKey('record.delete')));

      await tester.tap(find.byKey(const ValueKey('record.delete')));
      await tester.pumpAndSettle();

      expect(
        source.deleteCalls,
        0,
        reason: 'nothing may be deleted on one tap',
      );
      expect(find.text('Delete this record?'), findsOneWidget);
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      final source = FakeSource(recordPermissions: const {'delete': true});
      await tester.pumpWidget(viewHarness(source: source));
      await pumpUntilFound(tester, find.byKey(const ValueKey('record.delete')));

      await tester.tap(find.byKey(const ValueKey('record.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(source.deleteCalls, 0);
    });

    testWidgets('dismissing the dialog via the barrier deletes nothing', (
      tester,
    ) async {
      // showDialog resolves `null` on a barrier tap or a back-button pop,
      // same as it does on any dismissal that isn't the Delete button. The
      // guard is `confirmed != true`, which rejects `null` alongside
      // `false` — a later refactor to `if (confirmed == false) return;`
      // would silently start deleting on this path, and only this test
      // would catch it.
      final source = FakeSource(recordPermissions: const {'delete': true});
      await tester.pumpWidget(viewHarness(source: source));
      await pumpUntilFound(tester, find.byKey(const ValueKey('record.delete')));

      await tester.tap(find.byKey(const ValueKey('record.delete')));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(source.deleteCalls, 0);
    });

    testWidgets('a 404 is treated as already deleted, not as an error', (
      tester,
    ) async {
      // Someone else deleted it. Showing an error for a record that is gone
      // asks the user to retry something that already succeeded.
      final source = FakeSource(
        recordPermissions: const {'delete': true},
        deleteResult: const WriteGone('No [banners] record [7].'),
      );
      await tester.pumpWidget(viewHarness(source: source));
      await pumpUntilFound(tester, find.byKey(const ValueKey('record.delete')));

      await tester.tap(find.byKey(const ValueKey('record.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('No [banners] record [7].'), findsNothing);
      expect(source.deleteCalls, 1);
    });

    testWidgets('a 403 shows the server message', (tester) async {
      final source = FakeSource(
        recordPermissions: const {'delete': true},
        deleteResult: const WriteDenied('This action is unauthorized.'),
      );
      await tester.pumpWidget(viewHarness(source: source));
      await pumpUntilFound(tester, find.byKey(const ValueKey('record.delete')));

      await tester.tap(find.byKey(const ValueKey('record.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('This action is unauthorized.'), findsOneWidget);
    });

    // Two actions, one with a confirmation — shared by the action tests below.
    FakeSource actionSource({ActionResult? actionResult}) => FakeSource(
      recordActions: const [
        {'name': 'approve', 'label': 'Approve', 'color': 'success'},
        {
          'name': 'archive',
          'label': 'Archive',
          'color': 'gray',
          'confirmation': {
            'heading': 'Archive this?',
            'submit': 'Yes, archive',
            'cancel': 'Never mind',
          },
        },
      ],
      actionResult: actionResult ?? const ActionSuccess(null),
    );

    testWidgets('renders a button per published action', (tester) async {
      // The screen renders what the server published, in its order — it has
      // no list of its own and no opinion about which actions exist.
      await tester.pumpWidget(viewHarness(source: actionSource()));
      await _openActions(tester);

      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
    });

    testWidgets('renders no action affordance when the record publishes none', (
      tester,
    ) async {
      await tester.pumpWidget(viewHarness());
      await pumpUntilFound(tester, find.text('أحمد'));

      expect(find.byKey(const ValueKey('record.action.approve')), findsNothing);
    });

    testWidgets('an action with no confirmation runs on the first tap', (
      tester,
    ) async {
      final source = actionSource();
      await tester.pumpWidget(viewHarness(source: source));
      await _openActions(tester);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      // The source saw exactly one run, with the action's own name.
      expect(source.ranActions, ['approve']);
    });

    testWidgets(
      'an action with a confirmation runs only after the user confirms',
      (tester) async {
        final source = actionSource();
        await tester.pumpWidget(viewHarness(source: source));
        await _openActions(tester);

        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();

        // The dialog shows the action's OWN copy, not the package's generic
        // delete strings.
        expect(find.text('Archive this?'), findsOneWidget);
        expect(source.ranActions, isEmpty);

        await tester.tap(find.text('Yes, archive'));
        await tester.pumpAndSettle();

        expect(source.ranActions, ['archive']);
      },
    );

    testWidgets('cancelling a confirmation runs nothing', (tester) async {
      final source = actionSource();
      await tester.pumpWidget(viewHarness(source: source));
      await _openActions(tester);

      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Never mind'));
      await tester.pumpAndSettle();

      expect(source.ranActions, isEmpty);
    });

    testWidgets('a successful run re-fetches the record', (tester) async {
      // An action's most common effect is changing the permissions and
      // actions the screen is holding, so a stale record is a wrong screen.
      final source = actionSource();
      await tester.pumpWidget(viewHarness(source: source));
      await _openActions(tester);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(source.recordCalls, 2);
    });

    testWidgets(
      'a failed run shows the server message and leaves the record alone',
      (tester) async {
        final source = actionSource(
          actionResult: const ActionFailed('Cannot do that yet'),
        );
        await tester.pumpWidget(viewHarness(source: source));
        await _openActions(tester);

        await tester.tap(find.text('Approve'));
        await tester.pumpAndSettle();

        expect(find.text('Cannot do that yet'), findsOneWidget);
        expect(source.recordCalls, 1);
      },
    );

    testWidgets('a success the server said nothing about shows no snack bar', (
      tester,
    ) async {
      // Filament only sends a notification when the action declared a
      // title (`CanNotify::sendSuccessNotification()` guards on
      // `filled($title)`), so an action with no success title is SILENT on
      // the web panel. A `Cancel` reaches here the same way — 200 with a
      // null message — and inventing a "Done" toast for either one is the
      // phone claiming something the panel never said. The re-fetch is the
      // feedback: the record on screen changes.
      final source = actionSource(actionResult: const ActionSuccess(null));
      await tester.pumpWidget(viewHarness(source: source));
      await _openActions(tester);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      // Still re-fetched — silence is about the toast, not the refresh.
      expect(source.recordCalls, 2);
    });

    testWidgets(
      'a failure the server said nothing about still shows the fallback',
      (tester) async {
        // Deliberately NOT symmetric with the success case above, and
        // Filament's own asymmetry is the reason: it marks failure
        // notifications `->persistent()` and success ones not. On the web a
        // silent failure still leaves the user looking at a page that did
        // not change in a context they can read; on a phone, a tap that
        // produces nothing at all is indistinguishable from a dead button.
        final source = actionSource(actionResult: const ActionFailed(null));
        await tester.pumpWidget(viewHarness(source: source));
        await _openActions(tester);

        await tester.tap(find.text('Approve'));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(source.recordCalls, 1);
      },
    );

    testWidgets(
      'a fail-closed confirmation (empty submit/cancel) still prompts, '
      'with the client\'s own labels',
      (tester) async {
        // The server emits a non-null confirmation with empty submit/cancel
        // when its own evaluation throws — fail-closed, never "skip the
        // prompt". A blank-labelled button is the same defect as no prompt
        // at all, so this asserts on the visible label text, not just that
        // a button exists.
        final source = FakeSource(
          recordActions: const [
            {
              'name': 'archive',
              'label': 'Archive',
              'confirmation': {
                'heading': 'Archive this?',
                'submit': '',
                'cancel': '',
              },
            },
          ],
        );
        await tester.pumpWidget(viewHarness(source: source));
        await _openActions(tester);

        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();

        expect(find.text('Archive this?'), findsOneWidget);
        expect(find.text('Confirm'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(source.ranActions, isEmpty);

        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();

        expect(source.ranActions, ['archive']);
      },
    );

    testWidgets('a degraded action (label == name, no color/icon) still '
        'renders and still runs', (tester) async {
      // The server sends this exact shape when the panel's label/color/icon
      // closures threw — a cosmetic failure must never cost the user a
      // capability they are authorized to use.
      final source = FakeSource(
        recordActions: const [
          {'name': 'archive', 'label': 'archive'},
        ],
      );
      await tester.pumpWidget(viewHarness(source: source));
      await _openActions(tester);

      await tester.tap(find.text('archive'));
      await tester.pumpAndSettle();

      expect(source.ranActions, ['archive']);
    });

    testWidgets('renders in RTL without overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: ResourceViewScreen(
              provider: ResourceViewProvider(
                source: FakeSource(),
                resource: _resourceWith(const {'delete': true}),
                id: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('أحمد'), findsOneWidget);
    });

    const constrained = ValueKey('resource-view-constrained-content');

    testWidgets('at 1200px viewport, content is width-constrained by default', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(viewHarness());
      await pumpUntilFound(tester, find.text('أحمد'));

      expectWidthCapped(
        tester,
        find.byKey(constrained),
        cap: 720,
        viewportWidth: 1200,
      );
    });

    testWidgets('at 400px viewport, content is unconstrained by default', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(viewHarness());
      await pumpUntilFound(tester, find.text('أحمد'));

      expect(find.byKey(constrained), findsNothing);
      expectFullWidth(
        tester,
        find
            .descendant(
              of: find.byType(ResourceViewScreen),
              matching: find.byType(ListView),
            )
            .first,
        viewportWidth: 400,
      );
    });

    testWidgets('explicit maxContentWidth is honored', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ResourceViewScreen(
            provider: ResourceViewProvider(
              source: FakeSource(),
              resource: _resourceWith(const {'delete': true}),
              id: 1,
            ),
            maxContentWidth: 500,
          ),
        ),
      );
      await pumpUntilFound(tester, find.text('أحمد'));

      // 500 < the 720 default: only an applied value can satisfy this.
      expectWidthCapped(
        tester,
        find.byKey(constrained),
        cap: 500,
        viewportWidth: 1200,
      );
    });
  });

  group('relation sections', () {
    // Wire shape taken from the real BannerResource fixture — see
    // relation_descriptor_test.dart.
    const tagsRelation = {
      'key': 'tags',
      'label': 'Tags',
      'card': {
        'title': {'field': 'name'},
      },
    };

    testWidgets('a published relation renders as a section with its rows', (
      tester,
    ) async {
      final source = FakeSource(
        relationResult: PaginatedRecords(
          records: [
            ResourceRecord.fromJson(const {'id': 1, 'name': 'Sale'}, 'id'),
          ],
          meta: const PageMeta(
            currentPage: 1,
            lastPage: 1,
            perPage: 15,
            total: 1,
          ),
        ),
      );

      await tester.pumpWidget(
        viewHarness(source: source, relations: const [tagsRelation]),
      );
      await pumpUntilFound(tester, find.text('Sale'));

      expect(find.text('Tags'), findsOneWidget);
      // Proves the screen wired the RIGHT relation and record through —
      // `resource.key`/`record.id` are not hardcoded onto some other value.
      expect(source.relationCalls.single.resourceKey, 'users');
      expect(source.relationCalls.single.id, 1);
      expect(source.relationCalls.single.relationKey, 'tags');
    });

    testWidgets(
      'a published relation with zero rows shows an empty state, not an '
      'absent section',
      (tester) async {
        // Absence means the server did not publish the relation — see the
        // next test. Zero rows means it did, and this is what proves the two
        // still don't look the same once the fetch is wired inside the
        // package rather than by a host closure.
        final source = FakeSource(
          relationResult: const PaginatedRecords(
            records: [],
            meta: PageMeta(currentPage: 1, lastPage: 1, perPage: 15, total: 0),
          ),
        );

        await tester.pumpWidget(
          viewHarness(source: source, relations: const [tagsRelation]),
        );
        await pumpUntilFound(
          tester,
          find.byKey(const ValueKey('relation.empty')),
        );

        expect(find.text('Tags'), findsOneWidget);
      },
    );

    testWidgets(
      'a resource with no published relations renders no relation section '
      'at all',
      (tester) async {
        await tester.pumpWidget(viewHarness());
        await pumpUntilFound(tester, find.text('أحمد'));

        expect(find.byType(RelationSectionWidget), findsNothing);
      },
    );

    testWidgets(
      'a failed relation load degrades to a message at the screen, not an '
      'infinite spinner',
      (tester) async {
        // The HANDOFF pilot's permanent-spinner bug was a SCREEN, not a
        // widget in isolation — this is that lesson proven at the same
        // granularity, using FakeSource.relationError rather than the
        // widget-level fetch throw relation_section_test.dart already covers.
        final source = FakeSource(relationError: StateError('boom'));

        await tester.pumpWidget(
          viewHarness(source: source, relations: const [tagsRelation]),
        );
        await pumpUntilFound(
          tester,
          find.byKey(const ValueKey('relation.failed')),
        );

        expect(find.text('Tags'), findsOneWidget);
        expect(find.text('Could not load'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });
}
