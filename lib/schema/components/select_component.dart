part of '../schema_component.dart';

/// One choice in a [SelectComponent]. [value] stays untyped because the
/// contract allows ints (foreign keys) and strings (enums) alike.
class SelectOption extends Equatable {
  const SelectOption({required this.value, required this.label});

  factory SelectOption.fromJson(Map<String, dynamic> json, String path) {
    final value = json['value'];
    if (value == null) {
      throw SchemaFormatException('$path.value', 'expected a value, got null');
    }
    return SelectOption(
      value: value as Object,
      label: req<String>(json, 'label', path),
    );
  }

  final Object value;
  final String label;

  @override
  List<Object?> get props => [value];
}

/// Covers `select` and `multiselect`, and — via [optionsUrl] — BelongsTo
/// relations. A relation is a select with a URL, not a separate concept.
final class SelectComponent extends SchemaComponent {
  SelectComponent._({
    required _CommonProperties common,
    required this.options,
    required this.optionsUrl,
    required this.searchable,
    required this.multiple,
    required this.defaultValue,
  }) : super._common(common);

  factory SelectComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};
    final optionNodes = objects(config, 'options', '$path.config');
    return SelectComponent._(
      common: common,
      options: List.generate(
        optionNodes.length,
        (index) => SelectOption.fromJson(
          optionNodes[index],
          '$path.config.options[$index]',
        ),
      ),
      optionsUrl: opt<String>(config, 'optionsUrl'),
      searchable: opt<bool>(config, 'searchable') ?? false,
      multiple:
          common.type == 'multiselect' ||
          (opt<bool>(config, 'multiple') ?? false),
      defaultValue: json['default'],
    );
  }

  final List<SelectOption> options;

  /// Set when the option set is too large or too dynamic to inline. The
  /// client fetches and searches remotely instead.
  final String? optionsUrl;
  final bool searchable;
  final bool multiple;
  final Object? defaultValue;
}
