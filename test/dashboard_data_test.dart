import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an absent widgets key parses as an empty dashboard', () {
    // Every payload shape must parse; a missing key is an empty dashboard,
    // never a crash.
    expect(DashboardData.fromJson(const {}).widgets, isEmpty);
  });

  test('an absent direction key reads as ltr — a server predating Task 4b', () {
    expect(DashboardData.fromJson(const {}).direction, PanelDirection.ltr);
  });

  test('parses a published rtl direction', () {
    expect(
      DashboardData.fromJson(const {'direction': 'rtl'}).direction,
      PanelDirection.rtl,
    );
  });

  test('parses a stats widget, defaulting the optional fields', () {
    final data = DashboardData.fromJson(const {
      'widgets': [
        {
          'type': 'stats',
          'heading': 'Store overview',
          'description': 'Orders at a glance',
          'stats': [
            {
              'label': 'Orders',
              'value': '1340',
              'description': '12% increase',
              'descriptionIcon': 'heroicon-m-arrow-trending-up',
              'color': 'success',
              'chart': [7, 12, 9],
            },
            {'label': 'Refunds', 'value': '3'},
          ],
        },
      ],
    });

    final widget = data.widgets.single as StatsWidgetData;
    // The server now publishes both — the web panel renders them.
    expect(widget.heading, 'Store overview');
    expect(widget.description, 'Orders at a glance');
    expect(widget.stats, hasLength(2));
    expect(widget.stats.first.value, '1340');
    expect(widget.stats.first.chart, [7.0, 12.0, 9.0]);
    expect(widget.stats.last.description, isNull);
    expect(widget.stats.last.chart, isNull);
    expect(widget.stats.last.resourceKey, isNull);
  });

  test('parses a stat resourceKey — the mobile mirror of its web url', () {
    final data = DashboardData.fromJson(const {
      'widgets': [
        {
          'type': 'stats',
          'stats': [
            {'label': 'Drafts', 'value': '124', 'resourceKey': 'articles'},
          ],
        },
      ],
    });

    final widget = data.widgets.single as StatsWidgetData;
    expect(widget.stats.single.resourceKey, 'articles');
  });

  test('parses a chart widget', () {
    final data = DashboardData.fromJson(const {
      'widgets': [
        {
          'type': 'chart',
          'chartType': 'line',
          'heading': 'Revenue',
          'description': null,
          'labels': ['Jan', 'Feb'],
          'datasets': [
            {
              'label': 'Revenue',
              'data': [120, 340],
            },
          ],
        },
      ],
    });

    final widget = data.widgets.single as ChartWidgetData;
    expect(widget.chartType, 'line');
    expect(widget.heading, 'Revenue');
    expect(widget.labels, ['Jan', 'Feb']);
    expect(widget.datasets.single.data, [120.0, 340.0]);
  });

  test('skips a widget of an unknown type rather than throwing', () {
    // Forward compatibility: a server that grows a widget kind this build
    // does not know must not break the whole dashboard.
    final data = DashboardData.fromJson(const {
      'widgets': [
        {'type': 'sunburst'},
        {'type': 'stats', 'stats': []},
      ],
    });

    expect(data.widgets, hasLength(1));
    expect(data.widgets.single, isA<StatsWidgetData>());
  });

  test('a stat with no label or value is skipped, not rendered blank', () {
    final data = DashboardData.fromJson(const {
      'widgets': [
        {
          'type': 'stats',
          'stats': [
            {'value': '3'},
            {'label': 'Good', 'value': '7'},
          ],
        },
      ],
    });

    expect((data.widgets.single as StatsWidgetData).stats, hasLength(1));
  });
}
