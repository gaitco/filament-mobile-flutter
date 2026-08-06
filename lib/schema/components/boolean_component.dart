part of '../schema_component.dart';

enum BooleanKind { toggle, checkbox }

final class BooleanComponent extends SchemaComponent {
  BooleanComponent._({
    required _CommonProperties common,
    required this.kind,
    required this.defaultValue,
  }) : super._common(common);

  factory BooleanComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
  ) {
    return BooleanComponent._(
      common: common,
      kind: common.type == 'checkbox'
          ? BooleanKind.checkbox
          : BooleanKind.toggle,
      defaultValue: opt<bool>(json, 'default') ?? false,
    );
  }

  final BooleanKind kind;
  final bool defaultValue;
}
