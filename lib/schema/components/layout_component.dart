part of '../schema_component.dart';

enum LayoutKind { section, grid, tabs, fieldset }

/// A container node. Holds no value, so [name] is always null; the renderer
/// decides how each [kind] frames its [children].
final class LayoutComponent extends SchemaComponent {
  LayoutComponent._({
    required _CommonProperties common,
    required this.kind,
    required this.children,
    required this.collapsible,
    required this.collapsed,
    required this.columns,
  }) : super._common(common);

  factory LayoutComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
    int depth,
  ) {
    // Clamped, not rejected: P2 maps this onto a Flutter crossAxisCount, where
    // 0 or a negative is an assertion failure far from the JSON that caused it.
    final columns = opt<int>(json, 'columns') ?? 1;

    return LayoutComponent._(
      common: common,
      kind: switch (common.type) {
        'grid' => LayoutKind.grid,
        'tabs' => LayoutKind.tabs,
        'fieldset' => LayoutKind.fieldset,
        _ => LayoutKind.section,
      },
      children: SchemaComponent.listFromJson(json, 'children', path, depth + 1),
      collapsible: opt<bool>(json, 'collapsible') ?? false,
      collapsed: opt<bool>(json, 'collapsed') ?? false,
      columns: columns < 1 ? 1 : columns,
    );
  }

  final LayoutKind kind;
  final List<SchemaComponent> children;
  final bool collapsible;
  final bool collapsed;
  final int columns;
}
