part of '../schema_component.dart';

/// A repeater field: a list of rows built from a single item template.
///
/// [children] is that template — published **once**, not once per row. A
/// row's actual values live in the form state as a `List<Map>` under
/// [SchemaComponent.name]; rendering a row means walking this template once
/// per entry in that list, not re-parsing anything.
///
/// `readOnly` defaults to `true` so an older server that never publishes
/// [SchemaComponent] config for a repeater — meaning it predates repeater
/// support entirely — reads as inert rather than a renderer guessing it can
/// accept edits. Also `true` for a relationship repeater this build cannot
/// write to (out of scope this slice). `addable`/`deletable` default to
/// `false` for the same reason: no control an old server didn't declare.
final class RepeaterComponent extends SchemaComponent {
  RepeaterComponent._({
    required _CommonProperties common,
    required this.children,
    required this.addable,
    required this.deletable,
    required this.minItems,
    required this.maxItems,
    required this.itemLabel,
    required this.readOnly,
  }) : super._common(common);

  factory RepeaterComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
    int depth,
  ) {
    final config = object(json, 'config', path) ?? const {};
    return RepeaterComponent._(
      common: common,
      children: _templateFrom(json, path, depth),
      addable: opt<bool>(config, 'addable') ?? false,
      deletable: opt<bool>(config, 'deletable') ?? false,
      minItems: opt<int>(config, 'minItems'),
      maxItems: opt<int>(config, 'maxItems'),
      itemLabel: opt<String>(config, 'itemLabel'),
      readOnly: opt<bool>(config, 'readOnly') ?? true,
    );
  }

  /// Parses the item template one entry at a time so a single malformed
  /// child — missing `type`, a bad `config`, or not even an object — is
  /// dropped rather than failing the whole repeater (and with it, every
  /// other field on the form). `children` itself absent reads as an empty
  /// template; present but not a list is a genuine contract violation and
  /// throws, the same distinction [object] draws for a whole container
  /// arriving as the wrong shape.
  static List<SchemaComponent> _templateFrom(
    Map<String, dynamic> json,
    String path,
    int depth,
  ) {
    final raw = json['children'];
    if (raw == null) return const [];
    if (raw is! List) {
      throw SchemaFormatException(
        '$path.children',
        'expected List, got ${raw.runtimeType}',
      );
    }

    final children = <SchemaComponent>[];
    for (var index = 0; index < raw.length; index++) {
      final node = raw[index];
      if (node is! Map<String, dynamic>) continue;
      try {
        children.add(
          SchemaComponent.fromJson(node, '$path.children[$index]', depth + 1),
        );
      } on SchemaFormatException {
        continue;
      }
    }
    return children;
  }

  final List<SchemaComponent> children;
  final bool addable;
  final bool deletable;
  final int? minItems;
  final int? maxItems;
  final String? itemLabel;
  final bool readOnly;
}
