import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
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
}) {
  return MaterialApp(
    home: Scaffold(
      body: RelationSectionWidget(
        relation: _relation,
        recordId: '1',
        fetch: fetch,
        onSeeAllTap: onSeeAllTap,
      ),
    ),
  );
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
  });
}
