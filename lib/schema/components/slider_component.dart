part of '../schema_component.dart';

/// `slider`. [min]/[max]/[step] are presentation bounds for the control; the
/// enforceable half of the same declaration already arrives as the node's
/// ordinary `rules` (`required`/`numeric`/`min`/`max`, which Filament's
/// Slider force-registers server-side), so client-side validation needs no
/// slider-specific machinery at all.
///
/// The value is a number when [multiple] is false and a two-element `List`
/// when true. [multiple] is the server's `isMultiple()` read at walk time —
/// a range slider with no array default publishes `multiple: false` while
/// its rules still say `array` (a documented server weakness), so a `/state`
/// re-answer can flip it. The widget renders from whatever the node currently
/// says and never lets the client hint block a submission.
final class SliderComponent extends SchemaComponent {
  SliderComponent._({
    required _CommonProperties common,
    required this.min,
    required this.max,
    required this.step,
    required this.multiple,
    required this.defaultValue,
  }) : super._common(common);

  factory SliderComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};
    return SliderComponent._(
      common: common,
      // 0/100 are Filament's own accessor defaults; absent keys read as those,
      // never as an error.
      min: opt<num>(config, 'min') ?? 0,
      max: opt<num>(config, 'max') ?? 100,
      // Published only when the server's getStep() answers an int or float —
      // Filament allows a string step, which means "any step" here, not a
      // value to reinterpret.
      step: opt<num>(config, 'step'),
      multiple: opt<bool>(config, 'multiple') ?? false,
      defaultValue: json['default'],
    );
  }

  final num min;
  final num max;

  /// Null means no step constraint — the slider moves continuously.
  final num? step;
  final bool multiple;
  final Object? defaultValue;
}
