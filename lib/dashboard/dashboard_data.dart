import 'package:equatable/equatable.dart';

import '../schema/resource_schema.dart' show PanelDirection;

/// The dashboard's widgets, in the order the server published them.
///
/// Values only — a widget's *shape* is not published separately, because a
/// dashboard's numbers are computed per request and there is nothing static
/// to cache. Pull-to-refresh re-runs the queries.
class DashboardData extends Equatable {
  const DashboardData({
    this.widgets = const [],
    this.direction = PanelDirection.ltr,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final raw = json['widgets'];

    return DashboardData(
      widgets: [
        if (raw is List)
          for (final entry in raw)
            if (entry is Map<String, dynamic>)
              if (DashboardWidgetData.fromJson(entry) case final widget?)
                widget,
      ],
      // Absent reads as ltr — a server predating Task 4b, not a malformed
      // payload. See PanelDirection.fromJson's own doc for the same rule
      // applied to /schema's panel block.
      direction: PanelDirection.fromJson(json['direction']),
    );
  }

  final List<DashboardWidgetData> widgets;

  /// The panel's own layout direction — `GET /dashboard`'s half of the same
  /// answer `/schema`'s `panel.direction` publishes, so `DashboardScreen` can
  /// wrap itself without a host-facing parameter. See
  /// `withPanelDirection`'s doc for why this is resolved in `build()`, not a
  /// `State` method.
  final PanelDirection direction;

  @override
  List<Object?> get props => [widgets, direction];
}

/// Sealed so a caller's `switch` is exhaustive — the same shape as
/// `WriteResult` and `ActionResult`.
sealed class DashboardWidgetData extends Equatable {
  const DashboardWidgetData({this.heading});

  /// Null when the widget type this build does not know. A server that grows
  /// a widget kind must not break a dashboard that renders the rest — the
  /// same forward-compatibility rule the schema parser follows.
  static DashboardWidgetData? fromJson(Map<String, dynamic> json) =>
      switch (json['type']) {
        'stats' => StatsWidgetData.fromJson(json),
        'chart' => ChartWidgetData.fromJson(json),
        _ => null,
      };

  final String? heading;
}

/// A row of KPI stat cards — the panel's `StatsOverviewWidget` equivalent.
final class StatsWidgetData extends DashboardWidgetData {
  const StatsWidgetData({super.heading, this.description, required this.stats});

  static StatsWidgetData fromJson(Map<String, dynamic> json) {
    final raw = json['stats'];

    return StatsWidgetData(
      heading: json['heading'] is String ? json['heading'] as String : null,
      description: json['description'] is String
          ? json['description'] as String
          : null,
      stats: [
        if (raw is List)
          for (final entry in raw)
            if (entry is Map<String, dynamic>)
              if (StatData.fromJson(entry) case final stat?) stat,
      ],
    );
  }

  /// The widget's `getDescription()` — symmetric with [ChartWidgetData].
  final String? description;

  final List<StatData> stats;

  @override
  List<Object?> get props => [heading, description, stats];
}

/// One KPI card. [value] is always a string — the panel owns formatting
/// (currency, percentages, thousands separators) and the phone must not
/// re-derive or re-format it from a raw number.
class StatData extends Equatable {
  const StatData({
    required this.label,
    required this.value,
    this.description,
    this.descriptionIcon,
    this.color,
    this.chart,
  });

  /// Null when `label` or `value` is missing — a stat the client cannot
  /// render meaningfully is skipped, never shown with a blank number.
  static StatData? fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    final value = json['value'];
    if (label is! String || label.isEmpty) return null;
    if (value is! String) return null;

    return StatData(
      label: label,
      value: value,
      description: json['description'] is String
          ? json['description'] as String
          : null,
      descriptionIcon: json['descriptionIcon'] is String
          ? json['descriptionIcon'] as String
          : null,
      color: json['color'] is String ? json['color'] as String : null,
      chart: _numbers(json['chart']),
    );
  }

  final String label;
  final String value;
  final String? description;
  final String? descriptionIcon;

  /// A semantic colour name (`success`, `danger`, …) — the same vocabulary
  /// `RecordAction.color` uses.
  final String? color;

  /// The sparkline's data points, or null when the server sent none. An
  /// empty list is a chart with zero points this period — a normal state
  /// the sparkline draws as nothing — not a stand-in for "no chart".
  final List<double>? chart;

  @override
  List<Object?> get props => [
    label,
    value,
    description,
    descriptionIcon,
    color,
    chart,
  ];
}

/// A chart widget — one labelled axis shared by one or more [datasets].
final class ChartWidgetData extends DashboardWidgetData {
  const ChartWidgetData({
    super.heading,
    this.description,
    required this.chartType,
    required this.labels,
    required this.datasets,
  });

  static ChartWidgetData fromJson(Map<String, dynamic> json) {
    final rawLabels = json['labels'];
    final rawDatasets = json['datasets'];

    return ChartWidgetData(
      heading: json['heading'] is String ? json['heading'] as String : null,
      description: json['description'] is String
          ? json['description'] as String
          : null,
      chartType: json['chartType'] is String
          ? json['chartType'] as String
          : 'line',
      labels: [
        if (rawLabels is List)
          for (final label in rawLabels)
            if (label is String) label,
      ],
      datasets: [
        if (rawDatasets is List)
          for (final entry in rawDatasets)
            if (entry is Map<String, dynamic>)
              if (ChartDataset.fromJson(entry) case final dataset?) dataset,
      ],
    );
  }

  final String? description;
  final String chartType;
  final List<String> labels;
  final List<ChartDataset> datasets;

  @override
  List<Object?> get props => [
    heading,
    description,
    chartType,
    labels,
    datasets,
  ];
}

/// One series on a [ChartWidgetData]. A dataset whose `data` was not
/// entirely numeric was already dropped server-side — this build should
/// never see one — but parsing stays tolerant rather than trusting that.
class ChartDataset extends Equatable {
  const ChartDataset({this.label, required this.data});

  /// Null when `data` is missing or not entirely numeric — a series the
  /// client cannot plot is skipped, never plotted as zeros.
  static ChartDataset? fromJson(Map<String, dynamic> json) {
    final data = _numbers(json['data']);
    if (data == null) return null;

    return ChartDataset(
      label: json['label'] is String ? json['label'] as String : null,
      data: data,
    );
  }

  final String? label;
  final List<double> data;

  @override
  List<Object?> get props => [label, data];
}

/// Coerces a JSON list to doubles, or null when [raw] isn't a list, or one
/// of its entries isn't numeric — one bad element voids the whole series
/// rather than silently dropping just that point, which would shift every
/// later value against its label.
List<double>? _numbers(dynamic raw) {
  if (raw is! List) return null;

  final numbers = <double>[];
  for (final entry in raw) {
    if (entry is! num) return null;
    numbers.add(entry.toDouble());
  }
  return numbers;
}
