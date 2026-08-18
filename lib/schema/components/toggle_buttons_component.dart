part of '../schema_component.dart';

/// `toggle_buttons`. Carries the same flattened option shape `select`/`radio`
/// publish ([SelectOption]), but never an `optionsUrl` — the type has no
/// search affordance server-side, so an over-cap field inlines its full list
/// and this client renders however many options arrive.
///
/// The value is a scalar when [multiple] is false and a `List` when true —
/// the `select` vs `multiselect` split — through the ordinary
/// `default`/`/state`/write paths.
final class ToggleButtonsComponent extends SchemaComponent {
  ToggleButtonsComponent._({
    required _CommonProperties common,
    required this.options,
    required this.multiple,
    required this.defaultValue,
  }) : super._common(common);

  factory ToggleButtonsComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};
    final optionNodes = objects(config, 'options', '$path.config');
    return ToggleButtonsComponent._(
      common: common,
      options: List.generate(
        optionNodes.length,
        (index) => SelectOption.fromJson(
          optionNodes[index],
          '$path.config.options[$index]',
        ),
      ),
      // Always present on a current server; absent or wrong-typed reads as
      // single — the degradation rule every other config key already follows.
      multiple: opt<bool>(config, 'multiple') ?? false,
      defaultValue: json['default'],
    );
  }

  final List<SelectOption> options;
  final bool multiple;
  final Object? defaultValue;
}
