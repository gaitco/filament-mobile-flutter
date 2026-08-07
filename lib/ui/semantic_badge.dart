import 'package:flutter/material.dart';

import 'bidi_text.dart';

/// A value rendered as a chip, coloured by the semantic name the server maps
/// it to.
///
/// Shared by the card's badges and the infolist's `badge_entry` so both speak
/// the same colour language — a `status` that reads green in a list must not
/// read grey on the record it opens. It's also the *one* place both those
/// callers route a badge value through, which is why grouped-digit isolation
/// (fix round 1, P6f Task 5) lives here rather than in either caller: doing
/// it upstream, before [colors]' lookup, breaks the lookup itself — an
/// isolated key no longer matches the raw value the server mapped a colour
/// to.
class SemanticBadge extends StatelessWidget {
  const SemanticBadge({required this.value, required this.colors, super.key});

  final String value;

  /// Value → semantic colour name, straight from the contract.
  final Map<String, String> colors;

  /// Semantic colour names the server may send. An unmapped value falls
  /// through to the theme's default chip colour rather than an alarming one.
  static const _palette = <String, Color>{
    'success': Color(0xFF16A34A),
    'warning': Color(0xFFF59E0B),
    'danger': Color(0xFFDC2626),
    'info': Color(0xFF2563EB),
    'gray': Color(0xFF6B7280),
  };

  /// Looks up the colour for a semantic name (`success`, `danger`, …) — the
  /// same vocabulary this badge itself maps values through. Shared so a
  /// record action's own semantic colour and a badge entry's stay in the one
  /// place; null (unrecognised or absent) means "no opinion, use the theme's
  /// default".
  static Color? colorFor(String? semantic) =>
      semantic == null ? null : _palette[semantic];

  @override
  Widget build(BuildContext context) {
    // Keyed on the raw `value` — the server's own colour map, untouched.
    // Isolating first would break this lookup (fix round 1, finding 1).
    final colour = colorFor(colors[value]);

    return Chip(
      label: Text(isolateGroupedDigits(value, Directionality.of(context))),
      backgroundColor: colour?.withValues(alpha: 0.12),
      labelStyle: colour == null ? null : TextStyle(color: colour),
      visualDensity: VisualDensity.compact,
    );
  }
}
