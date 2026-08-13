import 'dart:async';

import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/dashboard_provider.dart';
import 'package:filament_mobile/ui/bidi_text.dart';
import 'package:filament_mobile/ui/dashboard_screen.dart';
import 'package:filament_mobile/ui/stat_sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_until_found.dart';

class FakeSource implements ResourceDataSource {
  FakeSource({this.dashboardData, this.error});

  final DashboardData? dashboardData;
  final Object? error;
  int dashboardCalls = 0;

  /// When set, `dashboard()` does not answer until it completes — so a test
  /// can observe the screen while a reload is in flight.
  Completer<void>? gate;

  @override
  Future<DashboardData> dashboard() async {
    dashboardCalls++;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return dashboardData ?? const DashboardData();
  }

  @override
  Future<PanelSchema> panel() async => throw UnimplementedError();

  @override
  Future<PanelSchema?> cachedPanel() async => null;

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
  Future<UploadResult> uploadFile(
    String resourceKey,
    String field, {
    required List<int> bytes,
    required String filename,
  }) => throw UnimplementedError();
}

Widget dashboardHarness({
  FakeSource? source,
  DashboardChartBuilder? chartBuilder,
}) {
  final resolvedSource = source ?? FakeSource();

  return MaterialApp(
    home: Scaffold(
      body: DashboardScreen(
        provider: DashboardProvider(resolvedSource),
        chartBuilder: chartBuilder,
      ),
    ),
  );
}

void main() {
  group('DashboardScreen', () {
    // Deliberately does NOT settle — same reasoning as the sibling test on
    // ResourceViewScreen and PanelIndexScreen: the provider is still
    // `initial` on the first frame, and a screen that treats that as
    // anything but loading flashes the empty state before the data arrives.
    testWidgets('the first frame is a skeleton, never empty', (tester) async {
      await tester.pumpWidget(dashboardHarness());

      expect(find.text('Nothing to show yet.'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('stat cards render their label and value', (tester) async {
      final source = FakeSource(
        dashboardData: DashboardData.fromJson(const {
          'widgets': [
            {
              'type': 'stats',
              'stats': [
                {'label': 'Orders', 'value': '1340'},
              ],
            },
          ],
        }),
      );
      await tester.pumpWidget(dashboardHarness(source: source));
      await pumpUntilFound(tester, find.text('Orders'));

      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('1340'), findsOneWidget);
    });

    // Fix round 1, finding 4: outside the original brief's three named
    // seams, `_statTile`'s `Text(stat.value)`/`Text(stat.description!)`
    // render a server-supplied string with no isolation at all — a stat
    // value is exactly where a grouped figure (a reference number, a
    // spaced total) shows up.
    testWidgets('a stat value with grouped digits is isolated under RTL', (
      tester,
    ) async {
      const value = '+20 2 2411 8610';
      final source = FakeSource(
        dashboardData: DashboardData.fromJson(const {
          'direction': 'rtl',
          'widgets': [
            {
              'type': 'stats',
              'stats': [
                {'label': 'Support', 'value': value},
              ],
            },
          ],
        }),
      );
      await tester.pumpWidget(dashboardHarness(source: source));
      await pumpUntilFound(tester, find.text('Support'));

      expect(find.text(isolateBidi(value, TextDirection.rtl)), findsOneWidget);
      expect(find.text(value), findsNothing);
    });

    testWidgets(
      'a stat with a chart renders a sparkline, one without renders none',
      (tester) async {
        final source = FakeSource(
          dashboardData: DashboardData.fromJson(const {
            'widgets': [
              {
                'type': 'stats',
                'stats': [
                  {
                    'label': 'Orders',
                    'value': '1340',
                    'chart': [1, 2, 3],
                  },
                  {'label': 'Refunds', 'value': '3'},
                ],
              },
            ],
          }),
        );
        await tester.pumpWidget(dashboardHarness(source: source));
        await pumpUntilFound(tester, find.text('Orders'));

        // Exactly one sparkline — for Orders, which published a chart — not
        // two, which would mean Refunds got one it never sent.
        expect(find.byType(StatSparkline), findsOneWidget);
      },
    );

    testWidgets(
      'an empty dashboard renders PanelEmpty, not a blank success screen',
      (tester) async {
        await tester.pumpWidget(dashboardHarness());
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('panel.empty')), findsOneWidget);
      },
    );

    testWidgets('a failure renders PanelFailure with a working retry', (
      tester,
    ) async {
      final source = FakeSource(error: Exception('boom'));
      await tester.pumpWidget(dashboardHarness(source: source));
      await tester.pumpAndSettle();

      expect(find.textContaining('boom'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(source.dashboardCalls, 2);
    });

    testWidgets('a 401 reaches PanelUnauthenticated, not a generic failure', (
      tester,
    ) async {
      final source = FakeSource(
        error: const FilamentTransportException(
          'Unauthenticated.',
          statusCode: 401,
        ),
      );
      await tester.pumpWidget(dashboardHarness(source: source));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('panel.unauthenticated')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a chart widget with no chartBuilder renders its heading and the '
      'chartUnavailable note, never a blank box',
      (tester) async {
        final source = FakeSource(
          dashboardData: DashboardData.fromJson(const {
            'widgets': [
              {
                'type': 'chart',
                'heading': 'Revenue',
                'chartType': 'line',
                'labels': ['Jan'],
                'datasets': [
                  {
                    'data': [120],
                  },
                ],
              },
            ],
          }),
        );
        await tester.pumpWidget(dashboardHarness(source: source));
        await pumpUntilFound(tester, find.text('Revenue'));

        expect(find.text('Revenue'), findsOneWidget);
        expect(find.text('No chart renderer supplied.'), findsOneWidget);
      },
    );

    testWidgets(
      'a chart widget WITH a chartBuilder renders exactly what the builder '
      'returned, and the builder receives the parsed ChartWidgetData',
      (tester) async {
        String? seenChartType;
        final source = FakeSource(
          dashboardData: DashboardData.fromJson(const {
            'widgets': [
              {
                'type': 'chart',
                'heading': 'Revenue',
                'chartType': 'bar',
                'labels': ['Jan'],
                'datasets': [
                  {
                    'data': [120],
                  },
                ],
              },
            ],
          }),
        );
        await tester.pumpWidget(
          dashboardHarness(
            source: source,
            chartBuilder: (context, data) {
              seenChartType = data.chartType;
              return const Text('custom chart widget');
            },
          ),
        );
        await pumpUntilFound(tester, find.text('custom chart widget'));

        expect(find.text('custom chart widget'), findsOneWidget);
        expect(find.text('No chart renderer supplied.'), findsNothing);
        expect(seenChartType, 'bar');
      },
    );

    testWidgets('pull-to-refresh re-reads the dashboard', (tester) async {
      final source = FakeSource(
        dashboardData: DashboardData.fromJson(const {
          'widgets': [
            {
              'type': 'stats',
              'stats': [
                {'label': 'Orders', 'value': '1'},
              ],
            },
          ],
        }),
      );
      await tester.pumpWidget(dashboardHarness(source: source));
      await pumpUntilFound(tester, find.text('Orders'));

      expect(source.dashboardCalls, 1);

      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await indicator.onRefresh();
      await tester.pumpAndSettle();

      expect(source.dashboardCalls, 2);
    });

    testWidgets(
      'a refresh keeps the current dashboard on screen — a real drag must '
      'not swap the body for a full-screen spinner mid-gesture',
      (tester) async {
        final source = FakeSource(
          dashboardData: DashboardData.fromJson(const {
            'widgets': [
              {
                'type': 'stats',
                'stats': [
                  {'label': 'Orders', 'value': '1340'},
                ],
              },
            ],
          }),
        );
        await tester.pumpWidget(dashboardHarness(source: source));
        await pumpUntilFound(tester, find.text('Orders'));

        // The reload stays in flight until the gate opens.
        source.gate = Completer<void>();
        await tester.fling(find.text('Orders'), const Offset(0, 300), 1000);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(source.dashboardCalls, 2, reason: 'the drag started a reload');
        // While the reload is in flight the previously loaded stat is STILL
        // on screen — the RefreshIndicator spins above it, but the body it
        // is attached to must not have been yanked out from under it.
        expect(find.text('Orders'), findsOneWidget);
        expect(find.text('1340'), findsOneWidget);

        source.gate!.complete();
        await tester.pumpAndSettle();

        expect(find.text('Orders'), findsOneWidget);
      },
    );
  });
}
