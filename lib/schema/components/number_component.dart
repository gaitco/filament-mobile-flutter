part of '../schema_component.dart';

final class NumberComponent extends SchemaComponent {
  NumberComponent._({
    required _CommonProperties common,
    required this.defaultValue,
    required this.prefix,
    required this.suffix,
  }) : super._common(common);

  factory NumberComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};
    return NumberComponent._(
      common: common,
      defaultValue: opt<num>(json, 'default'),
      prefix: opt<String>(config, 'prefix'),
      suffix: opt<String>(config, 'suffix'),
    );
  }

  final num? defaultValue;
  final String? prefix;
  final String? suffix;
}
