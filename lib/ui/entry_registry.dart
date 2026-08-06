import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../schema/schema_component.dart';
import 'entries/entry_widgets.dart';

typedef EntryBuilder =
    Widget Function(
      BuildContext context,
      SchemaComponent component,
      ResourceRecord record,
    );

/// The infolist half of rendering — `FieldRegistry` (`lib/form/field_registry.dart`)
/// is the form half. Registering a type here renders it on an infolist screen
/// and tells the server's ComponentTypeMap what name to emit; it says nothing
/// about how that type behaves as a form field, which is `FieldRegistry`'s
/// concern.
class EntryRegistry {
  EntryRegistry._(this._builders);

  factory EntryRegistry.defaults() => EntryRegistry._({});

  final Map<String, EntryBuilder> _builders;

  void register(String type, EntryBuilder builder) {
    _builders[type] = builder;
  }

  Widget build(
    BuildContext context,
    SchemaComponent component,
    ResourceRecord record,
  ) {
    final custom = _builders[component.type];
    if (custom != null) return custom(context, component, record);

    return switch (component) {
      LayoutComponent() => SectionTile(
        label: component.label,
        children: [
          for (final child in component.children) build(context, child, record),
        ],
      ),
      EntryComponent() => _entry(component, record),
      UnknownComponent() => _unknown(context, component, record),
      // A form field reaching an infolist screen renders nothing: P1 shows
      // only the infolist, and P2 owns forms.
      _ => const SizedBox.shrink(),
    };
  }

  Widget _entry(EntryComponent component, ResourceRecord record) {
    final value = component.name == null
        ? null
        : record.get<Object>(component.name!);

    return switch (component.kind) {
      EntryKind.boolean => BooleanEntryTile(
        label: component.label,
        value: value == true,
      ),
      EntryKind.image => ImageEntryTile(
        label: component.label,
        url: value is String ? value : null,
      ),
      EntryKind.badge => BadgeEntryTile(
        label: component.label,
        value: value?.toString(),
        colors: component.colors,
      ),
      EntryKind.text || EntryKind.date => EntryTile(
        label: component.label,
        value: value?.toString(),
      ),
    };
  }

  /// A type this build cannot render. Visible in debug so a developer sees it
  /// immediately; invisible in release so a user never meets a placeholder.
  ///
  /// The children render either way. Filament 5 ships containers this build
  /// does not know (`wizard`, `split`, `flex`, `actions`), and the parser keeps
  /// their children precisely so an unrecognised wrapper degrades to its
  /// contents rather than deleting a whole branch of the screen.
  Widget _unknown(
    BuildContext context,
    UnknownComponent component,
    ResourceRecord record,
  ) {
    final children = [
      for (final child in component.children) build(context, child, record),
    ];

    if (!kDebugMode && children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kDebugMode)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('⚠︎ unrenderable: ${component.type}'),
          ),
        ...children,
      ],
    );
  }
}
