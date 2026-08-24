import 'package:flutter/material.dart';

import '../dashboard/dashboard_data.dart';
import '../data/resource_record.dart';
import '../schema/resource_schema.dart';
import '../state/dashboard_provider.dart';
import '../state/panel_provider.dart';
import '../state/relation_list_provider.dart';
import '../state/resource_form_provider.dart';
import '../state/resource_list_provider.dart';
import '../state/resource_view_provider.dart';

/// Stable locations where an application can insert its own Flutter widgets.
///
/// Slots are deliberately semantic rather than pixel coordinates. This keeps
/// an application's extensions in the intended place when the package adapts
/// a screen between phone, tablet, desktop, LTR, and RTL layouts.
enum FilamentWidgetSlot {
  panelIndexBeforeContent,
  panelIndexAfterContent,
  dashboardBeforeContent,
  dashboardBeforeWidget,
  dashboardAfterWidget,
  dashboardAfterContent,
  resourceListBeforeContent,
  resourceListAfterContent,
  resourceViewBeforeContent,
  resourceViewBeforeRelations,
  resourceViewAfterContent,
  resourceFormBeforeFields,
  resourceFormAfterFields,
  resourceFormBeforeActions,
  resourceFormAfterActions,
  relationListBeforeContent,
  relationListAfterContent,
}

/// Builds an application-owned widget for a package-owned screen.
///
/// Returning null hides this registration for the current scope. That makes
/// one registry usable across a whole [PanelShell], while a builder can still
/// target a particular resource, record, or dashboard widget.
typedef FilamentWidgetBuilder =
    Widget? Function(BuildContext context, FilamentWidgetScope scope);

/// Screen-specific data supplied to a [FilamentWidgetBuilder].
sealed class FilamentWidgetScope {
  const FilamentWidgetScope();
}

final class PanelIndexWidgetScope extends FilamentWidgetScope {
  const PanelIndexWidgetScope({required this.provider});

  final PanelProvider provider;
}

final class DashboardWidgetScope extends FilamentWidgetScope {
  const DashboardWidgetScope({
    required this.provider,
    this.index,
    this.dashboardWidget,
  });

  final DashboardProvider provider;

  /// Set for [FilamentWidgetSlot.dashboardBeforeWidget] and
  /// [FilamentWidgetSlot.dashboardAfterWidget].
  final int? index;
  final DashboardWidgetData? dashboardWidget;
}

final class ResourceListWidgetScope extends FilamentWidgetScope {
  const ResourceListWidgetScope({required this.provider});

  final ResourceListProvider provider;
  ResourceSchema get resource => provider.resource;
}

final class ResourceViewWidgetScope extends FilamentWidgetScope {
  const ResourceViewWidgetScope({required this.provider, required this.record});

  final ResourceViewProvider provider;
  final ResourceRecord record;
  ResourceSchema get resource => provider.resource;
}

final class ResourceFormWidgetScope extends FilamentWidgetScope {
  const ResourceFormWidgetScope({required this.provider});

  final ResourceFormProvider provider;
  ResourceSchema get resource => provider.resource;
}

final class RelationListWidgetScope extends FilamentWidgetScope {
  const RelationListWidgetScope({
    required this.provider,
    required this.childResource,
  });

  final RelationListProvider provider;
  final ResourceSchema? childResource;
}

/// Ordered registry of application-owned widgets inserted into named slots.
///
/// A registry can be shared by every screen through [PanelShell.widgetRegistry]
/// or passed to an individual screen. Multiple builders registered for the
/// same slot render in registration order.
class FilamentWidgetRegistry {
  final Map<FilamentWidgetSlot, List<FilamentWidgetBuilder>> _builders = {};

  /// Registers a context-aware widget builder for [slot].
  void register(FilamentWidgetSlot slot, FilamentWidgetBuilder builder) {
    _builders.putIfAbsent(slot, () => []).add(builder);
  }

  /// Convenience for a fixed widget that does not need its screen scope.
  void registerWidget(FilamentWidgetSlot slot, Widget widget) {
    register(slot, (context, scope) => widget);
  }

  void unregister(FilamentWidgetSlot slot, FilamentWidgetBuilder builder) {
    final builders = _builders[slot];
    builders?.remove(builder);
    if (builders?.isEmpty ?? false) _builders.remove(slot);
  }

  void clear([FilamentWidgetSlot? slot]) {
    if (slot == null) {
      _builders.clear();
    } else {
      _builders.remove(slot);
    }
  }

  /// Builds a snapshot so a builder may safely update the registry for the
  /// next frame without mutating the list currently being traversed.
  List<Widget> build(
    FilamentWidgetSlot slot,
    BuildContext context,
    FilamentWidgetScope scope,
  ) {
    final builders = List<FilamentWidgetBuilder>.of(
      _builders[slot] ?? const [],
    );

    return [
      for (final builder in builders)
        if (builder(context, scope) case final widget?) widget,
    ];
  }
}
