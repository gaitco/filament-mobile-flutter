part of '../schema_component.dart';

enum EntryKind { text, badge, image, boolean, date, rich }

/// A read-only infolist entry. All five kinds display one field, so they share
/// one class; the extra slots are per-kind and null elsewhere.
final class EntryComponent extends SchemaComponent {
  EntryComponent._({
    required _CommonProperties common,
    required this.kind,
    required this.colors,
    required this.format,
    required this.fallback,
  }) : super._common(common);

  factory EntryComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};
    return EntryComponent._(
      common: common,
      kind: switch (common.type) {
        'badge_entry' => EntryKind.badge,
        'image_entry' => EntryKind.image,
        'boolean_entry' => EntryKind.boolean,
        'date_entry' => EntryKind.date,
        'rich_entry' => EntryKind.rich,
        _ => EntryKind.text,
      },
      colors: stringMap(config, 'colors'),
      format: opt<String>(config, 'format'),
      fallback: opt<String>(config, 'fallback'),
    );
  }

  final EntryKind kind;

  /// Value → semantic colour name, for [EntryKind.badge].
  final Map<String, String> colors;

  /// `intl` pattern, for [EntryKind.date].
  final String? format;

  /// Placeholder strategy, for [EntryKind.image].
  final String? fallback;
}
