part of '../schema_component.dart';

enum ColorFormat { hex, hsl, rgb, rgba }

/// `ColorPicker`. The panel declares one of four string formats via
/// `->hex()`/`->hsl()`/`->rgb()`/`->rgba()` — `getFormat()` is the ONLY
/// accessor `ColorPicker` exposes (measured in vendor/filament/forms/src/
/// Components/ColorPicker.php), and the value on the wire is a plain string
/// in that format. This client never converts it to another one: an `rgb`
/// field gets `rgb` back, byte for byte, everywhere it did not itself edit
/// the text.
///
/// No graphical picker, and no hand-rolled colour maths for one either: a
/// full HSV picker's conversion is easy to get subtly wrong and hard to
/// test, so the owner chose a text field with a live swatch instead (see the
/// P8 design doc). [match] is the one regex per format this client trusts —
/// copied from Filament's own documented validation patterns
/// (vendor/filament/forms/docs/17-color-picker.md, "Color picker
/// validation"), not invented — and it is the single place both
/// `client_validator.dart` (to block a malformed value at submission) and
/// `ColorFieldWidget` (to decide the swatch) read through, so "malformed"
/// cannot mean two different things in two places. It stays pure Dart
/// (`RegExp` only, no [Color]) — turning a match into an actual colour for
/// display is the widget's job, the same split [EntryComponent] draws
/// between a semantic colour NAME and a Flutter [Color].
final class ColorComponent extends SchemaComponent {
  ColorComponent._({
    required _CommonProperties common,
    required this.format,
    required this.defaultValue,
  }) : super._common(common);

  factory ColorComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};

    return ColorComponent._(
      common: common,
      // The server already normalises anything outside the closed set to
      // 'hex' (SchemaWalker's `color` branch), so `ifAbsent` here only
      // covers a server built before this field existed.
      format:
          _formats[closedEnum(
            config['format'],
            _formats.keys.toSet(),
            '$path.config.format',
            ifAbsent: 'hex',
          )]!,
      defaultValue: opt<String>(json, 'default'),
    );
  }

  static const Map<String, ColorFormat> _formats = {
    'hex': ColorFormat.hex,
    'hsl': ColorFormat.hsl,
    'rgb': ColorFormat.rgb,
    'rgba': ColorFormat.rgba,
  };

  final ColorFormat format;
  final String? defaultValue;

  /// Filament's own documented validation patterns
  /// (vendor/filament/forms/docs/17-color-picker.md), not invented — the
  /// same shapes a panel author would reach for with `->regex(...)`. No
  /// numeric range check beyond what these patterns themselves enforce
  /// (`rgb(999, 999, 999)` matches, exactly as it would against Filament's
  /// own suggested regex) — "malformed" means what Filament's own docs say
  /// it means, not a stricter rule this package invented on top.
  static final Map<ColorFormat, RegExp> _patterns = {
    ColorFormat.hex: RegExp(r'^#([a-fA-F0-9]{6}|[a-fA-F0-9]{3})$'),
    ColorFormat.rgb: RegExp(
      r'^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$',
    ),
    ColorFormat.rgba: RegExp(
      r'^rgba\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d*\.?\d+)\s*\)$',
    ),
    ColorFormat.hsl: RegExp(
      r'^hsl\(\s*(\d{1,3})\s*,\s*(\d{1,3}(?:\.\d+)?)%\s*,\s*(\d{1,3}(?:\.\d+)?)%\s*\)$',
    ),
  };

  /// Matches [raw] (leading/trailing whitespace ignored) against the pattern
  /// for [format]. Null means malformed — the single answer both a widget
  /// and a headless validator read.
  static RegExpMatch? match(String raw, ColorFormat format) =>
      _patterns[format]!.firstMatch(raw.trim());

  static bool isValid(String raw, ColorFormat format) =>
      match(raw, format) != null;
}
