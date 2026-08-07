import 'package:flutter/material.dart';

import '../dashboard/dashboard_data.dart';
import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';
import '../schema/resource_schema.dart' show PanelDirection;
import '../state/dashboard_provider.dart';
import 'bidi_text.dart';
import 'material_panel_state_builder.dart';
import 'stat_sparkline.dart';

/// Builds the widget for one [ChartWidgetData] — a host's own charting
/// library plotting the server's parsed labels and datasets.
typedef DashboardChartBuilder =
    Widget Function(BuildContext context, ChartWidgetData data);

/// The panel's dashboard: stat cards and, when the host supplies one, charts.
///
/// A plain widget with no router dependency, structured like
/// `PanelIndexScreen`: the host owns the provider and decides how this
/// screen is reached.
///
/// This package draws no charts of its own — it ships exactly two
/// dependencies (`flutter`, `equatable`), and that is a headline feature,
/// not an oversight. A chart widget with no [chartBuilder] renders its
/// heading and a "no chart renderer" note rather than pulling in a charting
/// package on the package's behalf. Do not "fix" that by adding one here;
/// the host supplies [chartBuilder] with whatever charting library it
/// already has.
///
/// Deliberately owns no `Scaffold`/`AppBar`, unlike its sibling screens:
/// `DashboardProvider` carries no title to put in one, so hosts wire this
/// screen directly into whatever chrome they already have.
///
/// **Wrapped in a `Directionality` resolved from the panel, same as its five
/// sibling screens** (Task 4b closes the gap Task 4 left stated here):
/// `GET /dashboard` now publishes its own `direction`, the same closed
/// `ltr`/`rtl` set `/schema`'s `panel.direction` does, and `DashboardData`
/// parses it. No host-facing parameter — the wrap reads the loaded data,
/// same as every other screen.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.provider,
    this.chartBuilder,
    this.stateBuilder,
    this.strings = const FilamentStrings(),
    super.key,
  });

  final DashboardProvider provider;
  final DashboardChartBuilder? chartBuilder;
  final PanelBodyBuilder? stateBuilder;
  final FilamentStrings strings;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Only an untouched provider is loaded, same reasoning as
    // PanelIndexScreen: the host owns the provider and may already have it
    // loaded from a previous visit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.provider.status.isInitial) widget.provider.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final builder =
        widget.stateBuilder ?? materialPanelStateBuilder(widget.strings);

    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) => withPanelDirection(
        widget.provider.data?.direction ?? PanelDirection.ltr,
        builder(context, _state()),
      ),
    );
  }

  PanelViewState _state() {
    final provider = widget.provider;

    // A reload with data already on screen keeps showing that data — a
    // pull-to-refresh must not swap the RefreshIndicator's own subtree for a
    // full-screen spinner mid-gesture. This is exactly the problem that made
    // ResourceViewScreen ship with NO pull-to-refresh (see its `_infolist`
    // doc); here refresh is a headline behaviour, so it refreshes in place.
    // Only the true first load (no data yet) shows the loading state.
    if ((provider.status.isLoading || provider.status.isInitial) &&
        provider.data == null) {
      return const PanelLoading();
    }

    if (provider.status.isFailure) {
      final message = provider.errorMessage ?? widget.strings.loadFailed;
      // Distinguished so a signed-out user is told they were signed out, not
      // that the server is broken — see PanelUnauthenticated's doc.
      if (provider.isUnauthenticated) {
        return PanelUnauthenticated(message: message, retry: provider.load);
      }
      return PanelFailure(message: message, retry: provider.load);
    }

    final widgets = provider.data?.widgets ?? const [];

    // A successful load of zero widgets is `PanelEmpty`, not the fallthrough
    // this screen exists to prevent — see the class doc.
    if (widgets.isEmpty) {
      return PanelEmpty(message: widget.strings.dashboardEmpty);
    }

    return PanelData(content: _list(widgets));
  }

  Widget _list(List<DashboardWidgetData> widgets) {
    return RefreshIndicator(
      // Values are live — see `ResourceDataSource.dashboard()` — so a pull
      // re-reads rather than replaying a cached document.
      onRefresh: widget.provider.load,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final entry in widgets)
            switch (entry) {
              StatsWidgetData() => _statsCard(entry),
              ChartWidgetData() => _chartCard(entry),
            },
        ],
      ),
    );
  }

  Widget _statsCard(StatsWidgetData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.heading != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text(
                data.heading!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          Wrap(children: [for (final stat in data.stats) _statTile(stat)]),
        ],
      ),
    );
  }

  Widget _statTile(StatData stat) {
    // NOT `Directionality.of(context)`: `context` here is this State's own
    // ambient context, an ANCESTOR of the `Directionality` `build()` wraps
    // around its returned widget (same trap `textDirectionOf`'s own doc
    // comment names, hit again here — caught by
    // `dashboard_screen_test.dart`'s RTL stat-value test failing against
    // `Directionality.of(context)` before this was fixed to read the
    // resolved value directly).
    final direction = textDirectionOf(
      widget.provider.data?.direction ?? PanelDirection.ltr,
    );

    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(stat.label, style: Theme.of(context).textTheme.bodySmall),
              Text(
                isolateBidi(stat.value, direction),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (stat.description != null)
                Text(isolateBidi(stat.description!, direction)),
              if (stat.chart != null) ...[
                const SizedBox(height: 8),
                StatSparkline(values: stat.chart!, color: stat.color),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chartCard(ChartWidgetData data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (data.heading != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  data.heading!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            widget.chartBuilder?.call(context, data) ??
                Text(widget.strings.chartUnavailable),
          ],
        ),
      ),
    );
  }
}
