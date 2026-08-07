import 'package:flutter/material.dart';

import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';
import '../schema/resource_schema.dart';
import '../state/panel_provider.dart';
import 'material_panel_state_builder.dart';

/// The panel's resources as a single list: the entry point once a user is
/// signed in.
///
/// A plain widget with no router dependency: the host decides where a tap
/// goes, exactly like ResourceListScreen.
///
/// A panel with a single resource may be opened directly by the caller
/// instead of showing this index — navigation belongs to the host, so this
/// screen deliberately does not implement that shortcut.
class PanelIndexScreen extends StatefulWidget {
  const PanelIndexScreen({
    required this.provider,
    required this.onResourceTap,
    this.stateBuilder,
    this.strings = const FilamentStrings(),
    super.key,
  });

  final PanelProvider provider;
  final void Function(ResourceSchema resource) onResourceTap;
  final PanelBodyBuilder? stateBuilder;
  final FilamentStrings strings;

  @override
  State<PanelIndexScreen> createState() => _PanelIndexScreenState();
}

class _PanelIndexScreenState extends State<PanelIndexScreen> {
  @override
  void initState() {
    super.initState();
    // Only an untouched provider is loaded, same reasoning as
    // ResourceListScreen: the host owns the provider and may already have it
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
        widget.provider.panel?.direction ?? PanelDirection.ltr,
        Scaffold(
          appBar: AppBar(title: Text(widget.provider.panel?.title ?? '')),
          body: builder(context, _state()),
        ),
      ),
    );
  }

  PanelViewState _state() {
    final provider = widget.provider;

    if (provider.status.isLoading || provider.status.isInitial) {
      return const PanelLoading();
    }

    if (provider.status.isFailure) {
      final message = provider.errorMessage ?? widget.strings.loadFailed;
      // Distinguished so a signed-out user is told they were signed out,
      // not that the server is broken — see PanelUnauthenticated's doc.
      if (provider.isUnauthenticated) {
        return PanelUnauthenticated(message: message, retry: provider.load);
      }
      return PanelFailure(message: message, retry: provider.load);
    }

    final resources = provider.panel?.resources ?? const [];

    // A successful load of zero resources is `PanelEmpty`, not `PanelLoading`
    // and not the fallthrough this screen exists to prevent — see the class
    // doc. `materialPanelStateBuilder` (and any host override) is responsible
    // for its `panel.empty` key, exactly like the sibling screens.
    if (resources.isEmpty) {
      return PanelEmpty(message: widget.strings.empty);
    }

    return PanelData(content: _list(resources));
  }

  /// Ungrouped resources first — this always matches Filament's own panel
  /// navigation — then each group under its heading, in the order `/schema`
  /// first lists it: this matches Filament only when the panel registers its
  /// group order explicitly via `->navigationGroups()`.
  Widget _list(List<ResourceSchema> resources) {
    final ungrouped = <ResourceSchema>[];
    final grouped = <String, List<ResourceSchema>>{};

    for (final resource in resources) {
      final group = resource.group;
      if (group == null) {
        ungrouped.add(resource);
      } else {
        grouped.putIfAbsent(group, () => []).add(resource);
      }
    }

    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (ungrouped.isNotEmpty) _card(ungrouped),
        for (final entry in grouped.entries) ...[
          Padding(
            key: ValueKey('panel.group.${entry.key}'),
            // Asymmetric, like a relation section's: a heading belongs to the
            // rows beneath it, and an even gap left it floating between the
            // card above and its own.
            padding: const EdgeInsetsDirectional.fromSTEB(4, 20, 4, 8),
            child: Text(
              entry.key,
              // Muted and tracked out rather than `labelLarge` at full
              // weight, which put a group name at the same visual rank as
              // the resources it names — so nothing on the screen led.
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
          _card(entry.value),
        ],
      ],
    );
  }

  /// One card per group, rows divided inside it. Bare `ListTile`s on the page
  /// background gave the index no structure at all — just resource names
  /// floating in space, with nothing saying they were tappable.
  Widget _card(List<ResourceSchema> resources) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < resources.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            _tile(resources[i]),
          ],
        ],
      ),
    );
  }

  Widget _tile(ResourceSchema resource) {
    return ListTile(
      title: Text(resource.labels.plural),
      // The glyph flips with the direction, not just its slot: `ListTile`
      // already moves `trailing` to the leading edge under RTL, but a
      // right-pointing chevron sitting on the left edge points back at the
      // text it is meant to lead away from.
      trailing: Icon(
        Directionality.of(context) == TextDirection.rtl
            ? Icons.chevron_left
            : Icons.chevron_right,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: () => widget.onResourceTap(resource),
    );
  }
}
