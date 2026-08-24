import 'dart:async';

import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/schema/resource_labels.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/resource_view_provider.dart';
import 'package:filament_mobile/ui/relation_section_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_until_found.dart';

const _relation = RelationDescriptor(
  key: 'tags',
  label: 'Tags',
  card: CardLayout(titleField: 'name'),
);

/// The same parsed shape `ResourceViewProvider.loadRelation` resolves to —
/// `RestResourceDataSource.relation()` already turned the wire envelope into
/// this. [rows] carries real field values so a test asserting rows rendered
/// is actually asserting against real data, not an empty array wearing a
/// passing test.
PaginatedRecords _page(
  List<Map<String, dynamic>> rows, {
  int currentPage = 1,
  int lastPage = 1,
}) {
  return PaginatedRecords(
    records: [
      for (final row in rows) ResourceRecord.fromJson(row, _relation.recordKey),
    ],
    meta: PageMeta(
      currentPage: currentPage,
      lastPage: lastPage,
      perPage: 15,
      total: rows.length,
    ),
  );
}

Widget _harness(
  Future<PaginatedRecords> Function({int page}) fetch, {
  void Function(RelationDescriptor relation, Object recordId)? onSeeAllTap,
  ResourceViewProvider? parent,
}) {
  return MaterialApp(
    home: Scaffold(
      body: RelationSectionWidget(
        relation: _relation,
        recordId: '1',
        fetch: fetch,
        parent: parent,
        onSeeAllTap: onSeeAllTap,
      ),
    ),
  );
}

const _resource = ResourceSchema(
  key: 'banners',
  labels: ResourceLabels(singular: 'Banner', plural: 'Banners'),
);

/// Serves the parent record for `ResourceViewProvider.load()` — the section's
/// own rows come from the test's `fetch` closure, never this source. The
/// hold/complete pair parks a load mid-flight so a test can observe the
/// `loading` notification on its own, before the `success` one lands.
class _RecordSource implements ResourceDataSource {
  @override
  Future<void> reorder(String resourceKey, List<Object> ids) =>
      throw UnimplementedError();
  Completer<ResourceRecord>? _held;

  void holdNextRecord() => _held = Completer<ResourceRecord>();

  void completeHeldRecord() =>
      _held!.complete(const ResourceRecord(id: 7, attributes: {'name': 'B'}));

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) {
    // Deliberately NOT consumed: `completeHeldRecord` completes this same
    // completer after the test has observed the loading notification, so it
    // must still be reachable here.
    final held = _held;
    if (held != null) return held.future;
    return Future.value(const ResourceRecord(id: 7, attributes: {'name': 'B'}));
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
    Map<String, Object?> filters = const {},
  }) => throw UnimplementedError();

  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) => throw UnimplementedError();

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

void main() {
  group('RelationSectionWidget', () {
    testWidgets('renders the relation label and its first rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ({int page = 1}) async => _page([
            {'id': 1, 'name': 'Sale'},
            {'id': 2, 'name': 'New arrival'},
          ]),
        ),
      );

      await pumpUntilFound(tester, find.text('Sale'));

      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('Sale'), findsOneWidget);
      expect(find.text('New arrival'), findsOneWidget);
    });

    testWidgets(
      'shows an empty state rather than vanishing when there are no rows',
      (tester) async {
        // Absence means the server did not publish the relation at all — see
        // ResourceViewScreen, which only builds a section per published
        // relation. Zero rows means the relation loaded fine and has
        // nothing in it — a real, successful response, not a stub standing
        // in for "never called".
        await tester.pumpWidget(
          _harness(({int page = 1}) async => _page(const [])),
        );

        await pumpUntilFound(
          tester,
          find.byKey(const ValueKey('relation.empty')),
        );

        expect(find.text('Tags'), findsOneWidget);
        expect(find.text('Nothing here yet'), findsOneWidget);
      },
    );

    testWidgets(
      'shows See all when there are more rows than the section shows',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            ({int page = 1}) async => _page(
              [
                {'id': 1, 'name': 'Sale'},
              ],
              currentPage: 1,
              lastPage: 2,
            ),
            onSeeAllTap: (relation, recordId) {},
          ),
        );

        await pumpUntilFound(tester, find.text('See all'));

        expect(find.text('See all'), findsOneWidget);
      },
    );

    testWidgets(
      'no See all when there is more to see but onSeeAllTap is unwired',
      (tester) async {
        // Sibling to the permission gates in gating_test.dart: absence means
        // unavailable, so an unwired host gets no button at all, never one
        // that renders enabled and silently no-ops on tap.
        await tester.pumpWidget(
          _harness(
            ({int page = 1}) async => _page(
              [
                {'id': 1, 'name': 'Sale'},
              ],
              currentPage: 1,
              lastPage: 2,
            ),
          ),
        );

        await pumpUntilFound(tester, find.text('Sale'));

        expect(find.text('See all'), findsNothing);
      },
    );

    testWidgets('no See all when the first page is the whole relation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ({int page = 1}) async => _page(
            [
              {'id': 1, 'name': 'Sale'},
            ],
            currentPage: 1,
            lastPage: 1,
          ),
        ),
      );

      await pumpUntilFound(tester, find.text('Sale'));

      expect(find.text('See all'), findsNothing);
    });

    testWidgets(
      'a transport failure degrades to a message, never an infinite spinner',
      (tester) async {
        // The pilot shipped a permanent spinner for a successful-but-
        // unauthorized load once already (see HANDOFF). This is that lesson
        // as a test: a genuine throw from `fetch` must resolve to a visible
        // failure state, not spin forever.
        await tester.pumpWidget(
          _harness(({int page = 1}) async => throw StateError('boom')),
        );

        await pumpUntilFound(
          tester,
          find.byKey(const ValueKey('relation.failed')),
        );

        expect(find.text('Could not load'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'a parse failure lands on the same message as a transport failure — '
      'documented, not accidental (see _load())',
      (tester) async {
        // `fetch` parses as part of resolving (`RestResourceDataSource
        // .relation()` builds every `ResourceRecord` before the Future
        // completes), so a row missing its `recordKey` throws the same shape
        // `ResourceRecord.fromJson` genuinely throws — an `ArgumentError` —
        // out of `fetch` itself, indistinguishable here from a socket error.
        // This test pins that documented trade-off: both throw shapes reach
        // `relation.failed`, never a bare unhandled exception and never a
        // stuck spinner.
        await tester.pumpWidget(
          _harness(
            ({int page = 1}) async =>
                throw ArgumentError('Record is missing its key `slug`.'),
          ),
        );

        await pumpUntilFound(
          tester,
          find.byKey(const ValueKey('relation.failed')),
        );

        expect(find.text('Could not load'), findsOneWidget);
      },
    );

    testWidgets('tapping See all calls back with the relation and record id', (
      tester,
    ) async {
      RelationDescriptor? tappedRelation;
      Object? tappedRecordId;

      await tester.pumpWidget(
        _harness(
          ({int page = 1}) async => _page(
            [
              {'id': 1, 'name': 'Sale'},
            ],
            currentPage: 1,
            lastPage: 2,
          ),
          onSeeAllTap: (relation, recordId) {
            tappedRelation = relation;
            tappedRecordId = recordId;
          },
        ),
      );

      await pumpUntilFound(tester, find.text('See all'));
      await tester.tap(find.text('See all'));
      await tester.pump();

      expect(tappedRelation, _relation);
      expect(tappedRecordId, '1');
    });

    group('parent reload (P9)', () {
      testWidgets('reloads its rows when the parent record finishes '
          'reloading — an action that changed membership no longer shows '
          'stale rows', (tester) async {
        final parent = ResourceViewProvider(
          source: _RecordSource(),
          resource: _resource,
          id: 7,
        );
        await parent.load();

        var fetches = 0;
        await tester.pumpWidget(
          _harness(parent: parent, ({int page = 1}) async {
            fetches++;
            return _page([
              {'id': 1, 'name': fetches == 1 ? 'Old row' : 'Fresh row'},
            ]);
          }),
        );
        await pumpUntilFound(tester, find.text('Old row'));
        expect(fetches, 1);

        await parent.load();
        await pumpUntilFound(tester, find.text('Fresh row'));

        expect(fetches, 2);
        expect(find.text('Old row'), findsNothing);
      });

      testWidgets('the parent going LOADING does not refetch — only the '
          'completed reload does', (tester) async {
        // The provider notifies twice per load; fetching on the first would
        // race the record the rows belong to (and double every fetch).
        final source = _RecordSource();
        final parent = ResourceViewProvider(
          source: source,
          resource: _resource,
          id: 7,
        );
        await parent.load();

        var fetches = 0;
        await tester.pumpWidget(
          _harness(parent: parent, ({int page = 1}) async {
            fetches++;
            return _page([
              {'id': 1, 'name': 'Row'},
            ]);
          }),
        );
        await pumpUntilFound(tester, find.text('Row'));
        expect(fetches, 1);

        source.holdNextRecord();
        final reload = parent.load();
        await tester.pump(); // the `loading` notification lands here

        expect(fetches, 1, reason: 'mid-load is not a reload');

        source.completeHeldRecord();
        await reload;
        await tester.pump();

        expect(fetches, 2);
      });

      testWidgets('a parent reload keeps the rows on screen — no spinner over '
          'a section that is already correct', (tester) async {
        final source = _RecordSource();
        final parent = ResourceViewProvider(
          source: source,
          resource: _resource,
          id: 7,
        );
        await parent.load();

        final gate = <Completer<PaginatedRecords>>[];
        await tester.pumpWidget(
          _harness(parent: parent, ({int page = 1}) {
            final completer = Completer<PaginatedRecords>();
            gate.add(completer);
            return completer.future;
          }),
        );

        // First load: nothing to keep, so a spinner is right.
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        gate.first.complete(
          _page([
            {'id': 1, 'name': 'Row one'},
          ]),
        );
        await pumpUntilFound(tester, find.text('Row one'));

        // Parent reload: the rows are still good, so they stay put while the
        // refetch is in flight. Flashing them away made a correct section look
        // like a first load on every record reload.
        await parent.load();
        await tester.pump();

        expect(gate.length, 2, reason: 'the reload did fetch');
        expect(find.text('Row one'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        gate.last.complete(
          _page([
            {'id': 1, 'name': 'Row two'},
          ]),
        );
        await pumpUntilFound(tester, find.text('Row two'));
      });

      testWidgets('two overlapping reloads settle in ASK order, not answer '
          'order — the stale page is dropped', (tester) async {
        final source = _RecordSource();
        final parent = ResourceViewProvider(
          source: source,
          resource: _resource,
          id: 7,
        );
        await parent.load();

        final gate = <Completer<PaginatedRecords>>[];
        await tester.pumpWidget(
          _harness(parent: parent, ({int page = 1}) {
            final completer = Completer<PaginatedRecords>();
            gate.add(completer);
            return completer.future;
          }),
        );
        await tester.pump();
        gate.first.complete(
          _page([
            {'id': 1, 'name': 'Original'},
          ]),
        );
        await pumpUntilFound(tester, find.text('Original'));

        // Two parent reloads in quick succession — a double pull-to-refresh.
        await parent.load();
        await tester.pump();
        await parent.load();
        await tester.pump();

        expect(gate.length, 3, reason: 'both reloads fetched');

        // The SECOND answers first, then the first answers late. Without the
        // request-id guard the late one wins and the section shows the page
        // nobody asked for last.
        gate[2].complete(
          _page([
            {'id': 1, 'name': 'Newest'},
          ]),
        );
        await pumpUntilFound(tester, find.text('Newest'));

        gate[1].complete(
          _page([
            {'id': 1, 'name': 'Superseded'},
          ]),
        );
        await tester.pump();

        expect(find.text('Newest'), findsOneWidget);
        expect(find.text('Superseded'), findsNothing);
      });

      testWidgets('a swapped parent (didUpdateWidget) is re-subscribed: the '
          'old provider no longer drives the section, the new one does', (
        tester,
      ) async {
        final old = ResourceViewProvider(
          source: _RecordSource(),
          resource: _resource,
          id: 7,
        );
        final swapped = ResourceViewProvider(
          source: _RecordSource(),
          resource: _resource,
          id: 8,
        );
        await old.load();
        await swapped.load();

        var fetches = 0;
        Future<PaginatedRecords> fetch({int page = 1}) async {
          fetches++;
          return _page([
            {'id': 1, 'name': 'Row'},
          ]);
        }

        await tester.pumpWidget(_harness(fetch, parent: old));
        await pumpUntilFound(tester, find.text('Row'));
        expect(fetches, 1);

        await tester.pumpWidget(_harness(fetch, parent: swapped));
        await tester.pump();
        // A swap alone is not a reload — same relation, same record.
        expect(fetches, 1);

        await old.load();
        await tester.pump();
        expect(fetches, 1, reason: 'the swapped-out provider is unheard');

        await swapped.load();
        await tester.pump();
        expect(fetches, 2);
      });
    });
  });
}
