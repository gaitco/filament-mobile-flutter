import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../schema/media_set.dart';
import '../schema/rich_document.dart';
import '../schema/schema_component.dart';
import 'component_direction.dart';
import 'entries/entry_widgets.dart';
import 'entries/rich_entry_tile.dart';

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
  EntryRegistry._(this._builders, {this.onLinkTap, this.onRelatedTap});

  factory EntryRegistry.defaults({
    void Function(String href)? onLinkTap,
    void Function(String resourceKey, Object recordId)? onRelatedTap,
  }) => EntryRegistry._({}, onLinkTap: onLinkTap, onRelatedTap: onRelatedTap);

  final Map<String, EntryBuilder> _builders;

  /// Forwarded to every `RichEntryTile` this registry builds. A host that
  /// wants tappable links constructs `EntryRegistry.defaults(onLinkTap: ...)`
  /// and passes it as `ResourceViewScreen.registry` — the same override
  /// point `signature_pad` uses in the tests, not a new one. Null (the
  /// default) means no host has wired it; see `RichEntryTile`'s doc for what
  /// that renders.
  final void Function(String href)? onLinkTap;

  /// Called with an entry's published target and the related record's id
  /// when a targeted entry is tapped — `category.name` navigating to that
  /// category. Same three-way gate as every affordance here: the server
  /// published a target, the record carries the id, AND the host wired
  /// this. Any half missing renders the plain entry, never one that
  /// ripples and silently no-ops.
  final void Function(String resourceKey, Object recordId)? onRelatedTap;

  void register(String type, EntryBuilder builder) {
    _builders[type] = builder;
  }

  Widget build(
    BuildContext context,
    SchemaComponent component,
    ResourceRecord record,
  ) {
    return buildWithComponentDirection(
      context,
      component.direction,
      (entryContext) => _build(entryContext, component, record),
    );
  }

  Widget _build(
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
      MapPointComponent() => _unsupportedKnown(context, component),
      UnknownComponent() => _unknown(context, component, record),
      // A form field reaching an infolist screen renders nothing: P1 shows
      // only the infolist, and P2 owns forms.
      _ => const SizedBox.shrink(),
    };
  }

  Widget _unsupportedKnown(BuildContext context, SchemaComponent component) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.extension_off_outlined),
        title: Text(component.label ?? component.name ?? component.type),
        subtitle: Text('Renderer not registered: ${component.type}'),
      ),
    );
  }

  Widget _entry(EntryComponent component, ResourceRecord record) {
    final value = component.name == null
        ? null
        : record.get<Object>(component.name!);

    final tile = switch (component.kind) {
      EntryKind.boolean => BooleanEntryTile(
        label: component.label,
        value: value == true,
      ),
      EntryKind.image => _imageEntry(component, value, record),
      EntryKind.badge => BadgeEntryTile(
        label: component.label,
        value: value?.toString(),
        colors: component.colors,
      ),
      EntryKind.rich => _richEntry(component, value, record),
      EntryKind.tags => _tagsEntry(component, value),
      EntryKind.text || EntryKind.date => EntryTile(
        label: component.label,
        value: value?.toString(),
      ),
    };

    return _relatedWrap(component, record, tile);
  }

  /// Wraps a targeted entry in a tap-through to its related record — see
  /// [onRelatedTap] for the gate. The id is read off the record at the
  /// path the server published beside the target; a payload missing it
  /// (an older server, a null relation) renders the plain tile.
  Widget _relatedWrap(
    EntryComponent component,
    ResourceRecord record,
    Widget tile,
  ) {
    final onRelatedTap = this.onRelatedTap;
    final resourceKey = component.targetResource;
    final recordPath = component.targetRecordPath;
    if (onRelatedTap == null || resourceKey == null || recordPath == null) {
      return tile;
    }

    final recordId = record.get<Object>(recordPath);
    if (recordId == null) return tile;

    return InkWell(
      key: ValueKey('entry.related.${component.name}'),
      onTap: () => onRelatedTap(resourceKey, recordId),
      child: tile,
    );
  }

  /// `EntryKind.image` reads `<name>.__media` — the flat sibling a
  /// medialibrary-backed field publishes beside its raw uuid token(s)
  /// (design spec, "Wire shape") — and renders the first item's display URL.
  /// No sibling (not a medialibrary field) falls back to the raw value as a
  /// URL, exactly as before this task.
  Widget _imageEntry(
    EntryComponent component,
    Object? value,
    ResourceRecord record,
  ) {
    final name = component.name;
    final media = name == null ? null : MediaSet.of(record, name);

    return ImageEntryTile(
      label: component.label,
      url: media != null && media.items.isNotEmpty
          ? media.items.first.displayUrl
          : (value is String ? value : null),
    );
  }

  /// `EntryKind.rich` reads `<name>.__rich` — the flat sibling
  /// `RecordSerializer` publishes beside the raw column (design spec, "Wire
  /// shape") — and renders the parsed document. No sibling (nothing to
  /// convert, or a `->prose()`-only entry `index()` never resolves for)
  /// falls back to the raw string, exactly like `text`/`date`: absence means
  /// unavailable, never a broken render.
  Widget _richEntry(
    EntryComponent component,
    Object? value,
    ResourceRecord record,
  ) {
    final name = component.name;
    final richJson = name == null
        ? null
        : record.get<Map<String, dynamic>>('$name.__rich');

    if (richJson == null) {
      return EntryTile(label: component.label, value: value?.toString());
    }

    return RichEntryTile(
      label: component.label,
      document: RichDocument.fromJson(richJson, '$name.__rich'),
      onLinkTap: onLinkTap,
    );
  }

  /// `EntryKind.tags` reads the record value straight off the path, the same
  /// way every non-media/rich kind does — no flat sibling, unlike
  /// `EntryKind.image`/`EntryKind.rich`, because a Spatie tags entry's value
  /// already travels as the same `List<String>` the writable `tags` field's
  /// does (`RecordSerializer::withTagPaths()`), nothing to nest and unwrap.
  /// A null or empty list, and a value that arrived as something other than
  /// a list (an older server, a crafted response), both fall back to the
  /// ordinary text treatment rather than rendering an empty or broken chip
  /// row.
  Widget _tagsEntry(EntryComponent component, Object? value) {
    if (value is List && value.isNotEmpty) {
      return TagsEntryTile(
        label: component.label,
        tags: [for (final tag in value) tag.toString()],
      );
    }

    if (value == null || value is List) {
      return EntryTile(label: component.label, value: null);
    }

    return EntryTile(label: component.label, value: value.toString());
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
